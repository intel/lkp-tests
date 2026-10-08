#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'set'
require 'yaml'
require "#{LKP_SRC}/lib/cache"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/lkp_pattern"
require "#{LKP_SRC}/lib/programs"

# Classifies a stat name as pass/fail/skip from etc/stat-classifier.yml
# (per-testcase word lists). An instance answers pass?/fail?/skip?/result?/
# type/patterns; the class-level failure_stat?/pass_stat?/skip_stat?/
# function_stat? wrap a shared default instance.
class StatClassifier
  def initialize(definitions = nil)
    definitions ||= LKP::Path.etc('stat-classifier.yml')

    # {"pass"=>{"*"=>"pass"}, "fail"=>{"*"=>"fail failed", "xfstests"=>"crash crashed warn"}, "skip"=>{"*"=>"skip block", "xfstests"=>"inconsistent_fs"}}
    @definitions = definitions.instance_of?(Hash) ? definitions : YAML.load_file(definitions)

    @regexps = @definitions.to_h do |type, hash|
      # (?:.+\.)? rather than (.+\.)*: .+ already spans dots, so both accept
      # the same strings, but the nested quantifier backtracks exponentially
      # on a stat name with many segments (e.g. a kmemleak backtrace).
      regexps = hash.map { |k, v| Regexp.new("^#{k == '*' ? '[^.]+' : k}\\.(?:.+\\.)?(#{v.split.join('|')})$", true) }
      [type, Regexp.union(regexps)]
    end

    instance_eval do
      @regexps.each do |type, regexp|
        define_singleton_method("#{type}?") do |stat|
          stat =~ regexp
        end
      end

      # rli9 FIXME: what if user specified result as definition key?
      define_singleton_method(:result?) do |stat|
        @result_regexp ||= Regexp.union(@regexps.values)

        stat =~ @result_regexp
      end
    end
  end

  def type(stat)
    # @regexps preserves the definitions file's top-level key order, and a
    # stat matching more than one type (e.g. a specific pass word plus a
    # sibling type's blanket catch-all for the same prefix) resolves to
    # whichever type is found first here -- see the comment above `pass:`
    # in etc/stat-classifier.yml.
    @regexps.find { |_type, regexp| stat =~ regexp }&.first
  end

  def patterns(type, test)
    @definitions[type].slice('*', test) # {"*"=>"fail failed", "xfstests"=>"crash crashed warn"}
                      .values
                      .flat_map(&:split)
  end

  class << self
    include Cacheable

    def function_stat?(stat)
      return false if stat.index('.time.')
      return false if stat.index('.timestamp:')
      return false if stat.index('.bootstage:')

      failure_stat?(stat) || pass_stat?(stat) || skip_stat?(stat)
    end
    cache_method :function_stat?

    def latency_stat?(stat)
      !LKP::IndexLatencyAll.instance.key(stat).nil?
    end
    cache_method :latency_stat?

    # The classifier built from etc/stat-classifier.yml, shared by the
    # *_stat? wrappers below.
    def default
      @default ||= new
    end

    # type is exclusive, so a stat that several types' patterns match (e.g.
    # kmsg.foo.pass) is reported by exactly one of these.
    def failure_stat?(stat)
      default.type(stat) == 'fail'
    end

    def pass_stat?(stat)
      default.type(stat) == 'pass'
    end

    def skip_stat?(stat)
      default.type(stat) == 'skip'
    end

    def memory_stat?(stat)
      LKP::MemoryStatPrefixes.instance.contain?(stat)
    end

    def bisectable_stat?(stat)
      return true if LKP::StatAllowlist.instance.contain?(stat)

      !LKP::StatDenylist.instance.contain?(stat)
    end

    KPI_STAT_DENYLIST = Set.new(['vm-scalability.stddev', 'unixbench.incomplete_result']).freeze

    def kpi_stat?(stat, _axes, _values = nil)
      return false if KPI_STAT_DENYLIST.include?(stat)

      base, _, remainder = stat.partition('.')
      LKP::Programs.all_tests_set.include?(base) && !remainder.start_with?('time.')
    end
  end
end
