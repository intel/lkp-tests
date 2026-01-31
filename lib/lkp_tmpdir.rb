#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

module LKP
  class TmpDir
    def initialize(prefix = nil)
      @path = Dir.mktmpdir prefix
      warn @path if ENV['debug'] == '1'

      yield self if block_given?
    end

    def add_permission
      FileUtils.chmod 'go+rwx', @path
    end

    def to_s
      @path
    end

    def path(*args)
      File.join([@path] + args)
    end

    def clean!
      FileUtils.rm_r(@path) unless ENV['debug'] == '1'
    end
  end
end
