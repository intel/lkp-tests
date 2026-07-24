#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__, 2)

require 'git'
require "#{LKP_SRC}/lib/string"

module Git
  class Lib
    def command_lines(*args, **kwargs)
      command_lines = command(*args, **kwargs)

      # to deal with "GIT error: cat-file ["commit", "9f86262dcc573ca195488de9ec6e4d6d74288ad3"]: invalid byte sequence in US-ASCII"
      # - one possibility is the encoding of string is wrongly set (due to unknown reason), e.g. UTF-8 string's encoding is set as US-ASCII
      #   thus to force_encoding to utf8_string and compare to error check of utf8_string, if same, will consider as wrong encoding info
      command_lines.resolve_invalid_bytes
                   .split("\n")
    end

    public :command_lines
    public :command
  end
end
