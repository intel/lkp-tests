#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'active_support/core_ext/string'
require 'singleton'
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/yaml"

module LKP
  class Pattern
    attr_reader :file

    def initialize(file)
      @file = file
    end

    def contain?(content)
      return false unless regexp

      Array(content).any? { |line| line =~ regexp }
    end

    def regexp
      return @regexp if @regexp
      return unless File.size?(file)

      @regexp = Regexp.new "(#{patterns.join('|')})"
    end

    def patterns
      @patterns ||= self.class.lines(file)
    end

    def pattern(content)
      patterns.find { |pattern| content =~ Regexp.new(pattern) }
    end

    class << self
      attr_reader :klass_2_path

      def generate_klass(file_path, klass_name = nil)
        @klass_2_path ||= {}

        klass_name ||= File.basename(file_path).underscore.camelize
        return if @klass_2_path.key?(klass_name)

        klass = Class.new(self) do
          include Singleton

          def initialize
            super(self.class.superclass.klass_2_path[self.class.name])
          end
        end

        LKP.const_set klass_name, klass

        @klass_2_path[klass.name] = file_path
      end

      def lines(file)
        File.readlines(file)
            .map(&:chomp)
            .reject(&:empty?)
            .reject { |line| line.start_with?('#') }
      end
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
  end

  # generate class like LKP::StatDenylist
  %w[event-counter-patterns dmesg-kill-pattern report-allowlist stat-allowlist stat-denylist oops-pattern perf-metrics-patterns].each do |file_name|
    LKP::Pattern.generate_klass(LKP::Path.src('etc', file_name))
  end
end
