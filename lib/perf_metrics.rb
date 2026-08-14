#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/lkp_pattern"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/programs"
require "#{LKP_SRC}/lib/yaml"

LKP_SRC_ETC ||= LKP::Path.src('etc')

module LKP
  class PerfMetrics
    include Singleton

    def initialize
      prefix_patterns = LKP::PerfMetricsPrefixes.instance.patterns

      additional_prefixes = LKP::Programs.test_prefixes.reject do |test|
        test_name = test[0..-2]
        functional_test?(test_name) || other_test?(test_name) || %w(kmsg dmesg stderr last_state).include?(test_name)
      end

      patterns = prefix_patterns + additional_prefixes.map { |prefix| Regexp.escape(prefix) }
      @regexp = Regexp.new "^(#{patterns.join('|')})"
    end

    def contain?(name)
      @cache ||= {}

      return @cache[name] if @cache.key? name

      @cache[name] = LKP::PerfMetricsPatterns.instance.contain?(name) || @regexp.match?(name)
    end
  end
end
