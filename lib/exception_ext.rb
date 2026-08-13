#!/usr/bin/env ruby

class Exception
  def formatted_headline
    "#{backtrace.first}: #{message.split("\n").first} (#{self.class.name})"
  end

  def formatted_body
    # a literal tab here (instead of leading spaces) makes libyaml refuse to
    # emit call_stack as a readable literal block scalar, forcing an
    # escaped/quoted one-liner instead
    backtrace[1..].map { |m| "  from #{m}" }
  end

  def call_stack
    [formatted_headline, formatted_body].flatten
  end
end
