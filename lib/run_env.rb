#!/usr/bin/env ruby
LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)
LOCAL_RUN_ENV ||= 'LKP_LOCAL_RUN'.freeze

require 'yaml'
require "#{LKP_SRC}/lib/bash"

def __local_run?
  hostname = Bash.run('hostname').chomp
  return false unless File.exist?("#{LKP_SRC}/hosts/#{hostname}")

  host_file = YAML.load_file("#{LKP_SRC}/hosts/#{hostname}")
  host_file['local_run'] == 1
end

def local_run?
  env_is_local = ENV.fetch(LOCAL_RUN_ENV, nil)
  if env_is_local != '1' && env_is_local != '0'
    env_is_local = __local_run? ? '1' : '0'
    ENV[LOCAL_RUN_ENV] = env_is_local
  end
  env_is_local == '1'
end

def set_local_run
  ENV[LOCAL_RUN_ENV] = '1'
end
