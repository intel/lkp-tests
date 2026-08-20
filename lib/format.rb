#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'term/ansicolor'
require "#{LKP_SRC}/lib/markdownable"
require "#{LKP_SRC}/lib/time"

def humanize_time(seconds)
  seconds = seconds.to_i

  days, seconds = seconds.divmod(1.day.to_i)
  hours, seconds = seconds.divmod(1.hour.to_i)
  minutes, seconds = seconds.divmod(1.minute.to_i)

  if days.positive?
    format('%2d:%02d:%02d:%02d', days, hours, minutes, seconds)
  elsif hours.positive?
    format('%4d:%02d:%02d', hours, minutes, seconds)
  elsif minutes.positive?
    format('%7d:%02d', minutes, seconds)
  else
    format('%10d', seconds)
  end
end

module LKP
  module Format
    class << self
      def completion(completed, total, options = {})
        str = (completed == total ? completed.to_s : "#{completed}/#{total}")

        str = "#{completed * 100 / total}% (#{str})" if options[:percentage]

        str
      end

      # 160 33.1% kernel test robot
      def count_with_percentage(count, sum, name)
        format('%4d %4s%% %s', count, (count * 100 / sum.to_f).round(1), name)
      end

      # convert [1,2,3,4,5,8,9,11] to "1 - 5, 8 - 9, 11" to avoid long output
      def condensed_ranges(numbers, increment = 1)
        numbers.sort
               .uniq # [1,2,3,4,5,8,9,11]
               .inject([]) { |memo, i| (memo.last && memo.last[1] + increment == i ? memo.last[1] = i : memo << [i, i]) && memo } # [[1,5],[8,9],[11,11]]
               .map { |item| item[0] == item[1] ? item[0] : "#{item[0]} - #{item[1]}" } # ['1 - 5','8 - 9','11']
               .join(', ')
      end
    end
  end
end

class String
  include Term::ANSIColor
  include Markdownable
end
