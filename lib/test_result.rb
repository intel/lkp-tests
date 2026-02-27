#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/bisect_kpi"
require "#{LKP_SRC}/lib/dirable"
require "#{LKP_SRC}/lib/result"
require "#{LKP_SRC}/lib/string"
require "#{LKP_SRC}/lib/test_result_definition"

module LKP
  # rli9 FIXME need better name for XTestResult, results, etc
  class FuncTestResult
    attr_reader :test, :results

    # results is like [:pass, :fail, 'fail', :fail] that provides the results of multiple runs
    def initialize(test, results)
      @test = test

      # convert to { pass: 1, fail: 3 }
      @results = case results
                 when Array
                   results.map(&:to_sym)
                          .tally
                 when Hash
                   results.transform_keys(&:to_sym)
                 else
                   { results.to_sym => 1 }
                 end
    end

    def result
      return :skip if results[:skip]

      return :unstable if results[:pass] && results[:fail]
      return :pass if results[:pass]
      return :fail if results[:fail]

      :unknown
    end
  end

  BootTestResult = FuncTestResult

  class PerfTestResult
    attr_reader :test, :results

    def initialize(test, results)
      @test = test
      @results = Array(results)
    end

    def result
      results.first
    end
  end

  module TestResultable
    include Dirable

    def result_path
      return @result_path if @result_path

      @result_path = ResultPath.new

      is_local_run = if content_size?('job.yaml')
                       job_yaml = YAML.unsafe_load_file content_path('job.yaml')
                       job_yaml['LKP_LOCAL_RUN'] == 1
                     end

      # support both /result and /result/bad path
      raise ArgumentError, "Invalid path #{path}" unless @result_path.parse_result_root(path.sub(/^#{RESULT_ROOT_DIR}(\/bad)?/o, ''), is_local_run: is_local_run)

      @result_path
    end

    def spec
      return @spec if @spec

      @spec = YAML.unsafe_load_file(content_path('job.yaml')) if content_size?('job.yaml')
      @spec ||= {}
    end

    def gcommit
      return @gcommit if @gcommit

      @gcommit = Git.open.gcommit(self['commit'])
    end

    def kcmdline(param = nil)
      kcmdline = [self['kernel_cmdline'], self['kernel_cmdline_hw']].compact.join(' ')

      param ? kcmdline.match(/#{param}=([^\s]+)/) { |m| m[1] } : kcmdline
    end

    %w[vmalloc swiotbl].each do |param|
      define_method("kcmdline_#{param}") do
        kcmdline(param)
      end
    end

    def test_results
      return {} unless test_contents

      boot_test_results.merge(func_test_results)
                       .merge(perf_test_results)
    end

    def base(base_kernel)
      base_path = path.sub(self['commit'], base_kernel)

      self.class.new(base_path) if Dir.exist?(base_path)
    end

    def base_test_results(base_kernel)
      base = base(base_kernel)
      return {} unless base

      base.test_results
    end

    def func_test_results
      return {} unless test_contents

      test_contents.reject { |test_stat, _values| LKP::StatDenylist.instance.contain?(test_stat) }
                   .select { |test_stat, _values| test_stat =~ /^#{self['testcase']}/ && self.class.test_result_definition.result?(test_stat) }
                   .to_h do |test_stat, values|
        result = self.class.test_result_definition.type(test_stat)

        # "kmsg.XFS(pmem#):EXPERIMENTAL_online_scrub_feature_in_use.Use_at_your_own_risk": 1,
        #
        # "xfstests.generic.413.pass": 1,
        #
        # kernel-selftests.android.run.sh.fail: {
        #   0,
        #   1
        # }
        # "kernel-selftests.kvm.make.fail": [
        #   1
        # ]
        values = Array(values)
        log_warn "#{test_stat} value is unexpected | #{values}" unless values.any?(&:positive?)

        [test_stat, FuncTestResult.new(test_stat.sub(/\.(pass|fail|skip)$/, ''), result => values.sum)]
      end
    end

    def boot_test_results
      return {} unless test_contents

      allowed_stats = %w[
        dmesg.BUG
        dmesg.WARNING
        dmesg.Oops
        last_state.OOM
        last_state.soft_timeout
      ]

      test_results = test_contents.select { |test_stat, _values| test_stat =~ /^(#{allowed_stats.map { |s| Regexp.escape(s) }.join('|')})/ }
                                  .to_h do |test_stat, values|
        result = self.class.test_result_definition.type(test_stat)
        values = Array(values)

        [test_stat, BootTestResult.new(test_stat, result => values.sum)]
      end

      if %w[boot fuzz].include?(rectified_category)
        test_results['dmesg.boot_succeeded'] = BootTestResult.new('dmesg.oops', :pass) unless test_results['dmesg.boot_failures']
        test_results['last_state.completed'] = BootTestResult.new('last_state', :pass) unless test_results['last_state.is_incomplete_run']
      end

      test_results
    end

    def perf_test_results
      return {} unless test_contents

      bisect_kpi = LKP::PerfKpi.new

      test_contents.reject { |test_stat, _values| LKP::StatDenylist.instance.contain?(test_stat) }
                   .select { |test_stat, _values| test_stat =~ /^#{self['testcase']}/ && bisect_kpi.match?(test_stat) }
                   .to_h do |test_stat, values|
        [test_stat, PerfTestResult.new(test_stat, values)]
      end
    end

    def rectified_category
      case self['testcase']
      when /boot/
        'boot'
      when /trinity|locktorture|rcuscale|rcutorture|syzkaller/
        'fuzz'
      when /rcurefscale/
        'benchmark'
      else
        self['category']
      end
    end

    class << self
      def included(mod)
        class << mod; include ClassMethods; end
      end
    end

    module ClassMethods
      def test_result_definition
        @test_result_definition ||= TestResultDefinition.new
      end
    end
  end
end
