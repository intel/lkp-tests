#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'active_support/core_ext/string'
require "#{LKP_SRC}/lib/time"

REGEX_ANSI_COLOR = /\e\[([0-9;]+m|[mK])/
class String
  # for converting log lines into "Content-Type: text/plain;" emails
  def plain_text
    remove(REGEX_ANSI_COLOR)
      .tr("\r", "\n")
      .remove(/[^[:print:]\n]/)
  end

  # invalid byte sequence in US-ASCII (ArgumentError)
  def resolve_invalid_bytes(options = { replace: '_' })
    return self if valid_encoding?

    clone.force_encoding('UTF-8')
         .encode('UTF-8', 'UTF-8', **options, invalid: :replace, undef: :replace)
  end

  def strip_nonprintable_characters
    remove(/[^[:print:]]/)
  end

  def numeric?
    !Float(self).nil?
  rescue StandardError
    false
  end

  def uncolorize
    remove(/\e\[(\d+)?(;\d+)?(;\d+)?m/).remove(/\e\[K/)
  end

  def unicode_escape
    str = chars.map do |char|
      if char.ascii_only?
        char
      else
        char.codepoints.map { |cp| "\\u#{cp.to_s(16).rjust(4, '0')}" }.join
      end
    end

    str.join
  end
end
