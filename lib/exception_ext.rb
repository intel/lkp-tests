#!/usr/bin/env ruby

class Exception
  def formatted_headline
    "#{backtrace.first}: #{message.split("\n").first} (#{self.class.name})"
  end

  def formatted_body
    backtrace[1..].map { |m| "\tfrom #{m}" }
  end

  def call_stack
    [formatted_headline, formatted_body].flatten
  end
end
