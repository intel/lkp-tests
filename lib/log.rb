#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'logger'

LOG_FORMATTER = proc do |severity, datetime, _progname, msg|
  msg = if msg.is_a? Exception
          ["#{msg.backtrace.first}: #{msg.message.split("\n").first} (#{msg.class.name})", msg.backtrace[1..].map { |m| "\tfrom #{m}" }].flatten
        else
          msg.to_s.split("\n")
        end

  msg.map { |m| "#{datetime} #{severity} -- #{m}\n" }.join
end

class Log
  class << self
    attr_accessor :out, :err
  end

  self.out = Logger.new($stdout)
  out.formatter = LOG_FORMATTER

  self.err = Logger.new($stderr)
  err.formatter = LOG_FORMATTER
end

# below methods are available
#   - log_debug
#   - log_info
%w(debug info).each do |severity|
  define_method("log_#{severity}") do |*args, &block|
    Log.out.send(severity, *args, &block)
  end
end

alias log log_info

# below methods are available
#   - log_warn
#   - log_error
%w(warn error).each do |severity|
  define_method("log_#{severity}") do |*args, &block|
    Log.err.send(severity, *args, &block)
  end
end

def log_verbose(...)
  return unless ENV['LKP_VERBOSE']

  Log.out.debug(...)
end
