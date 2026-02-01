require 'spec_helper'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/yaml"

describe 'check the format correctness of etc files' do
  def yaml_file?(file)
    file =~ /\.(yaml|yml)$/
  end

  def pattern_file?(file)
    # exclude suffixed files and executable files
    file !~ /\.\w+$/ && Bash.run("head -1 #{file}") !~ %r{#!(/bin/bash|/bin/sh|/usr/bin/ruby)}
  end

  it 'yaml file loaded as yaml' do
    Bash.run("find #{LKP_SRC}/etc -type f").split("\n").select { |file| yaml_file?(file) }.each do |file|
      expect { load_yaml(file) }.not_to raise_error
    end
  end

  it 'pattern file loaded by grep -E -f <pattern_file>' do
    Bash.run("find #{LKP_SRC}/etc -type f").split("\n").select { |file| pattern_file?(file) }.each do |file|
      # here we use /dev/null as the target file of grep command, so it will always return 1
      # we just need to make sure there is no bash error when loading the pattern file
      expect { Bash.run("grep -q -E -f #{file} /dev/null", returns: [1]) }.not_to raise_error
    end
  end

  it 'pattern file loaded as ruby regexp' do
    Bash.run("find #{LKP_SRC}/etc -type f").split("\n").select { |file| pattern_file?(file) }.each do |file|
      File.readlines(file).each do |line|
        expect { Regexp.new(line) }.not_to raise_error
      end
    end
  end
end
