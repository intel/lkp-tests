#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'ostruct'
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/statistics"
require "#{LKP_SRC}/lib/stats"

module LKP
  class PerfKpi
    attr_reader :patterns

    def initialize(options = {})
      @patterns = load_yaml LKP::Path.etc('index-perf-all.yaml')
      @patterns = @patterns.merge(load_yaml(LKP::Path.etc('index-latency-all.yaml')))

      @patterns = @patterns.reject { |k, _v| k =~ options[:deny_pattern] } if options[:deny_pattern]
      # pattern: "will-it-scale\\..+_ops", 1
      @patterns = @patterns.map { |k, v| PerfStatPattern.new(k, v) }
    end

    # return: [["will-it-scale.per_process_ops", ["will-it-scale\\..+_ops", 1]]]
    def stats(stats)
      stats = stats.map do |stat|
        pattern = patterns.find { |pattern| pattern.match?(stat) }

        pattern && PerfStat.new(stat, pattern)
      end

      stats.compact
    end

    def match?(stat)
      patterns.any? { |pattern| pattern.match?(stat) }
    end
  end

  class PerfStat
    attr_reader :stat, :pattern

    def initialize(stat, pattern)
      @stat = stat
      @pattern = pattern
    end

    def statistics(matrix)
      return unless matrix[stat]

      # round(0) to fix Numerical argument is out of domain - "sqrt" (Math::DomainError)
      values = samples_remove_boot_fails(matrix, matrix[stat]).map(&:round)
      return if values.empty?

      result = OpenStruct.new(min: values.min,
                              mean: values.average,
                              max: values.max,
                              min_max_gap: (values.max - values.min) / values.min.to_f * 100,
                              rstd: values.relative_stddev,
                              size: values.size)
      result[:stable] = [result.min_max_gap, result.rstd].all? { |v| v <= 20 }

      result
    end

    def change(base_matrix, matrix)
      return unless base_matrix[stat] && matrix[stat]

      values = samples_remove_boot_fails(matrix, matrix[stat])
      base_values = samples_remove_boot_fails(base_matrix, base_matrix[stat])

      percentage = ((values.average - base_values.average) / base_values.average * 100).round(1) * pattern.sign

      OpenStruct.new(percentage: percentage)
    end

    def best(values)
      pattern.sign.positive? ? values.max : values.min
    end

    def stable?(_mrt)
      true
    end

    def to_s
      "(#{stat}, #{pattern})"
    end
  end

  class PerfStatPattern
    attr_reader :regexp, :direction

    def initialize(regexp, direction)
      @regexp = regexp
      @direction = direction
    end

    def match?(stat)
      stat =~ /^#{regexp}$/
    end

    def sign
      direction.positive? ? 1 : -1
    end

    def to_s
      "#{regexp}: #{direction}"
    end
  end

  class BootKpi
    attr_reader :patterns, :deny_patterns

    def initialize(_options = {})
      # negative value means regression (the less the better)
      @patterns = {
        /dmesg\..+/ => -1,
        /last_state\.load_disk_fail/ => -1
      }

      @patterns = @patterns.map { |k, v| FuncStatPattern.new(k, v) }

      @deny_patterns = {
        /dmesg\.timestamp.+/ => 0,
        /dmesg\.bootstage.+/ => 0,
        /dmesg\.boot_failures/ => 0
      }

      @deny_patterns = @deny_patterns.map { |k, v| FuncStatPattern.new(k, v) }
    end

    def stats(stats)
      stats = stats.map do |stat|
        pattern = patterns.find { |pattern| pattern.match?(stat) }
        deny_pattern = deny_patterns.find { |pattern| pattern.match?(stat) }

        next unless pattern && deny_pattern.nil?

        BootStat.new(stat, pattern)
      end

      stats.compact
    end

    def match?(stat)
      patterns.any? { |pattern| pattern.match?(stat) }
    end
  end

  class BootStat
    attr_reader :stat, :pattern

    def initialize(stat, pattern)
      @stat = stat
      @pattern = pattern
    end

    # if curr doesn't have, the change is nil
    # if curr has && base has, the percentage is 0
    # if curr has && base doesn't have, the percentage is 100
    def change(base_matrix, matrix)
      return unless matrix[stat]&.max&.positive?

      values = matrix[stat]
      base_values = base_matrix[stat]

      percentage = if base_values&.max&.positive?
                     ((values.max - base_values.max) / base_values.max * 100) * pattern.sign # this must/should be 0
                   else
                     values.max * 100 * pattern.sign
                   end

      OpenStruct.new(percentage: percentage)
    end

    def to_s
      "(#{stat}, #{pattern})"
    end

    def stability(mrt)
      return 'N/A' unless mrt.test_contents && mrt.test_contents[stat]

      values = mrt.test_contents[stat]
      return 'N/A' if values.empty?

      stability = values.sum.to_s
      stability += "/#{mrt.stats_size}" if mrt.stats_size != values.sum
      stability += " (#{mrt.complete_runs})" if mrt.complete_runs != mrt.stats_size
      stability
    end

    # consider as "prefer to bisect" check
    def stable?(mrt)
      return false unless mrt.test_contents && mrt.test_contents[stat]

      values = mrt.test_contents[stat]
      return false if values.empty?

      (values.sum * 100 / mrt.stats_size) > 20 # 20% possibility
    end
  end

  class FuncKpi
    attr_reader :patterns, :deny_patterns

    def initialize(_options = {})
      # negative value means regression (the less the better)
      @patterns = {
        /.+\.(error|warn|fail)$/ => -1
      }

      @patterns = @patterns.map { |k, v| FuncStatPattern.new(k, v) }
    end

    def stats(stats)
      stats = stats.map do |stat|
        # perf-profile.self.cycles-pp.error_ent
        # perf-profile.children.cycles-pp.error
        next if stat =~ /^perf-profile/

        pattern = patterns.find { |pattern| pattern.match?(stat) }
        next unless pattern

        FuncStat.new(stat, pattern)
      end

      stats.compact
    end

    def match?(stat)
      patterns.any? { |pattern| pattern.match?(stat) }
    end
  end

  class FuncStat
    attr_reader :stat, :pattern

    def initialize(stat, pattern)
      @stat = stat
      @pattern = pattern
    end

    # if curr doesn't have, the change is nil
    # if curr has && base has, the percentage is 0
    # if curr has && base doesn't have, the percentage is 100
    def change(base_matrix, matrix)
      return unless matrix[stat]&.max&.positive?

      values = matrix[stat]
      base_values = base_matrix[stat]

      if base_values&.max&.positive?
        percentage = ((values.max - base_values.max) / base_values.max * 100) * pattern.sign # this must/should be 0
      else
        base_values = base_matrix[reverse_stat(stat)]
        return unless base_values&.max&.positive?

        percentage = values.max * 100 * pattern.sign
      end

      OpenStruct.new(percentage: percentage)
    end

    def to_s
      "(#{stat}, #{pattern})"
    end

    def stability(mrt)
      reverse_stat = reverse_stat(stat)

      values = mrt.test_contents[stat] || []
      reverse_values = mrt.test_contents[reverse_stat] || []

      stability = values.sum.to_s
      stability += "-#{reverse_values.sum}" unless reverse_values.sum.zero?
      stability += "/#{mrt.stats_size}" if mrt.stats_size != (values.sum + reverse_values.sum)
      stability += " (#{mrt.complete_runs})" if mrt.complete_runs != mrt.stats_size
      stability
    end

    # consider as "prefer to bisect" check
    def stable?(mrt)
      reverse_stat = reverse_stat(stat)

      reverse_values = mrt.test_contents[reverse_stat] || []
      return false unless reverse_values.sum.zero?

      true
    end

    def reverse_stat(stat)
      stat.sub(/\.[^.]+$/, '.pass')
    end
  end

  class FuncStatPattern
    attr_reader :regexp, :direction

    def initialize(regexp, direction)
      @regexp = regexp.instance_of?(Regexp) ? regexp : /^#{regexp}$/
      @direction = direction
    end

    def match?(stat)
      stat =~ regexp
    end

    def sign
      direction.positive? ? 1 : -1
    end

    def to_s
      "#{regexp}: #{direction}"
    end
  end
end
