#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'singleton'
require 'yaml'
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/string"

module LKP
  # Shared by any class whose subclasses are generated on demand, one per
  # backing file, and cached as a Singleton keyed by that file's path (see
  # Pattern and PatternValues below).
  module KlassGenerator
    def klass_2_path
      @klass_2_path ||= {}
    end

    def generate_klass(file_path, klass_name = nil, **new_args)
      klass_name ||= File.basename(file_path).underscore.camelize
      return if klass_2_path.key?(klass_name)

      klass = Class.new(self) do
        include Singleton

        define_method(:initialize) do
          super(self.class.superclass.klass_2_path[self.class.name], **new_args)
        end
      end

      LKP.const_set klass_name, klass

      klass_2_path[klass.name] = file_path
    end
  end

  # Combines each non-empty, non-comment line of file into one regex,
  # substring-matched against content by default. anchor: controls where
  # that match is required to land:
  # - :none (default): anywhere in content, e.g. etc/stat-denylist
  # - :start: start of content, e.g. etc/failure's "dmesg.*" matching
  #   "dmesg.INFO:..." but not "notdmesg.foo"
  # - :full: the entire content, e.g. etc/add-max-latency's
  #   "numa-meminfo.node[0-9].AnonPages" matching that stat exactly but
  #   not "numa-meminfo.node0.AnonPagesExtra"
  class Pattern
    attr_reader :file

    def initialize(file, anchor: :none)
      @file = file
      @anchor = anchor
    end

    def contain?(content)
      return false unless regexp

      Array(content).any? { |line| line =~ regexp }
    end

    def regexp
      return @regexp if @regexp
      return unless File.size?(file)

      combined = "(#{patterns.join('|')})"
      combined = "^#{combined}" if @anchor == :start || @anchor == :full
      combined = "#{combined}$" if @anchor == :full
      @regexp = Regexp.new combined
    end

    def patterns
      @patterns ||= self.class.lines(file)
    end

    def pattern(content)
      patterns.find { |pattern| content =~ Regexp.new(pattern) }
    end

    class << self
      include KlassGenerator

      def lines(file)
        File.readlines(file)
            .map(&:chomp)
            .reject(&:empty?)
            .reject { |line| line.start_with?('#') }
      end
    end
  end

  # Caches a YAML file whose keys are themselves patterns, e.g.
  # "dmesg.*(BUG|PANIC): 50" in etc/weight.yaml - the opposite shape from
  # KeysPatterns below, where the *values* are the patterns. Callers look
  # values up through #value/#key/#[] rather than reaching into the
  # underlying hash directly, so the on-disk shape stays free to change.
  class PatternValues
    def initialize(file)
      @data = YAML.load_file file
    end

    # Mirrors KeysPatterns#key, but for the opposite shape: finds the first
    # key (a pattern) that content matches, and returns its associated
    # value instead of the key itself.
    def value(content)
      match = @data.find { |pattern, _value| content =~ %r{^#{pattern}} }
      match&.last
    end

    # Finds the first key (a pattern) that fully matches content, e.g.
    # matching a stat name against etc/index-perf-all.yaml's patterns.
    # exclude, if given, drops candidate keys matching that regex first.
    def key(content, exclude: nil)
      keys = @data.keys
      keys = keys.grep_v(exclude) if exclude
      keys.find { |pattern| content =~ /^#{pattern}$/ }
    end

    def [](key)
      @data[key]
    end

    def keys
      @data.keys
    end

    def to_h
      @data.dup
    end

    class << self
      include KlassGenerator
    end
  end

  class KeysPatterns
    def initialize(file)
      @keys_patterns = YAML.load_file file
      @keys_patterns = @keys_patterns.transform_values { |v| Regexp.new Array(v).join('|') }
    end

    def key(value)
      find = @keys_patterns.find { |_k, regexp| value =~ regexp }
      find&.first
    end

    def value(key)
      @keys_patterns[key]
    end

    class << self
      include KlassGenerator
    end
  end

  # generate class like LKP::StatDenylist
  %w[event-counter-patterns dmesg-kill-pattern report-allowlist stat-allowlist stat-denylist oops-pattern perf-metrics-patterns].each do |file_name|
    LKP::Pattern.generate_klass(LKP::Path.src('etc', file_name))
  end

  # generate class like LKP::EventCounterPrefixes
  %w[event-counter-prefixes independent-counter-prefixes ignore-part-prefixes].each do |file_name|
    LKP::Pattern.generate_klass(LKP::Path.src('etc', file_name), anchor: :start)
  end

  # generate LKP::Failure, LKP::Pass
  %w[failure pass].each do |file_name|
    LKP::Pattern.generate_klass(LKP::Path.src('etc', file_name), anchor: :start)
  end

  # generate LKP::AddMaxLatency
  LKP::Pattern.generate_klass(LKP::Path.src('etc', 'add-max-latency'), anchor: :full)

  # generate LKP::HistorySummary, LKP::PatchApply, LKP::ScheduleGcovTest
  {
    'history-summary.yml' => 'HistorySummary',
    'patch-apply.yml' => 'PatchApply',
    'schedule-gcov-test.yml' => 'ScheduleGcovTest'
  }.each do |file_name, klass_name|
    LKP::KeysPatterns.generate_klass(LKP::Path.src('etc', file_name), klass_name)
  end

  # generate LKP::MemoryStatPrefixes
  LKP::Pattern.generate_klass(LKP::Path.src('etc', 'memory-stat-prefixes'), anchor: :start)

  # generate LKP::PerfMetricsThreshold, LKP::IndexPerfAll, LKP::IndexLatencyAll, LKP::IndexPower, LKP::IndexSize, LKP::IndexLatency
  {
    'perf-metrics-threshold.yaml' => 'PerfMetricsThreshold',
    'index-perf-all.yaml' => 'IndexPerfAll',
    'index-latency-all.yaml' => 'IndexLatencyAll',
    'index-power.yaml' => 'IndexPower',
    'index-size.yaml' => 'IndexSize',
    'index-latency.yaml' => 'IndexLatency'
  }.each do |file_name, klass_name|
    LKP::PatternValues.generate_klass(LKP::Path.src('etc', file_name), klass_name)
  end

  # generate LKP::LinuxPerfTestCases, LKP::LinuxTestCases, LKP::OtherTestCases
  %w[linux-perf-test-cases linux-test-cases other-test-cases].each do |file_name|
    LKP::Pattern.generate_klass(LKP::Path.src('etc', file_name), anchor: :full)
  end

  # generate LKP::PerfMetricsPrefixes
  LKP::Pattern.generate_klass(LKP::Path.src('etc', 'perf-metrics-prefixes'), anchor: :start)
end
