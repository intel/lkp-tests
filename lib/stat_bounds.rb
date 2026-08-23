#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/cache"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/yaml"

class StatBounds
  class << self
    include Cacheable

    def valid?(stats_field, num)
      monitor = stats_field.split('.')[0]
      stats_range = range_for(monitor)

      stats_range&.each do |k, v|
        next unless stats_field =~ %r{^#{k}$}

        min = v[0]
        max = v[1]
        return false if num < min || num > max
      end

      true
    end

    def range_for(monitor)
      range_file = LKP::Path.etc("valid-range-#{monitor}.yaml")
      File.exist?(range_file) ? JSON.parse_cached(range_file) : nil
    end
    cache_method :range_for, cache_nil: true
  end
end
