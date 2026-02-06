require 'rubygems'
require 'bundler/setup'
require 'rake/file_utils'
require 'rspec/core/rake_task'
require 'fileutils'
require 'rubocop/rake_task'
require 'English'

desc 'Show help'
task :help do
  puts <<-EOF
## SPEC

usage
  rake spec [spec=result_path]

example
  rake spec                       # check all unit tests status
  rake spec spec=job              # check spec/job_spec.rb status

## RUBOCOP

usage
  rake rubocop [file=pattern]

example
  rake rubocop file="lib/**/*.rb" # check all lib files
  EOF
end

RSpec::Core::RakeTask.new do |t|
  ENV['LKP_SRC'] ||= File.expand_path File.dirname(__FILE__).to_s

  puts "PWD = #{Dir.pwd}"
  puts "ENV['LKP_SRC'] = #{ENV.fetch('LKP_SRC', nil)}"

  spec = ENV['spec'] || '*'
  t.pattern = "spec/**{,/*/**}/#{spec}_spec.rb"
  t.rspec_opts = "--example '#{ENV['example']}'" if ENV['example']
end

if ENV['GENERATE_REPORTS'] == 'true'
  require 'ci/reporter/rake/rspec'
  task spec: 'ci:setup:rspec'
end

begin
  RuboCop::RakeTask.new(:rubocop) do |t|
    ruby_version = `ruby --version | grep -oE "[0-9]+\\.[0-9]+"`.chomp

    rubocop_config_file = ".rubocop.#{ruby_version}.yml"
    rubocop_config_file = '.rubocop.yml' unless File.size?(rubocop_config_file)

    t.options = ['-D', "-c#{rubocop_config_file}"]
    t.patterns = [ENV['file']] if ENV['file']

    puts "PWD = #{Dir.pwd}"
    puts "rubocop.patterns = #{t.patterns}"
    puts "rubocop.options = #{t.options}"
  end
rescue StandardError => e
  puts e
end

desc 'Run syntax check'
task :syntax do
  executables = `find -type f -executable ! -path "./.git*" ! -path "./vendor*" ! -size +100k`.split("\n").join(' ')

  sh "grep -s -l '^#!/.*ruby$' #{executables} | xargs -P$(nproc) -n1 ruby -c >/dev/null", verbose: false
  sh "grep -s -l '^#!/.*bash$' #{executables} | xargs -P$(nproc) -n1 bash -n", verbose: false
  sh "grep -s -l '^#!/bin/sh$' #{executables} | xargs -P$(nproc) -n1 dash -n", verbose: false

  puts 'syntax OK'
end

desc 'Run shellcheck'
task :shellcheck do
  executables = ENV['file'] || `find -type f -executable ! -path "./.git*"  ! -path "./vendor*" ! -size +100k | xargs -P$(nproc) grep -s -l -e '^#!/.*bash$' -e '^#!/bin/sh$'`.split("\n").join(' ')

  format = ENV['format'] || 'tty'

  base_cmd = "shellcheck -S warning -f #{format}"
  base_cmd += " -i #{ENV['code']}" if ENV['code']

  sh "#{base_cmd} #{executables}", verbose: false

  puts 'shellcheck OK'
end

desc 'Run yamllint'
task :yamllint do
  sh 'yamllint', '--strict', '--format=auto', '.'

  puts 'yamllint OK'
end

desc 'Run code check'
task code: %i[syntax shellcheck rubocop spec]

namespace :docker do
  desc 'Build docker image'
  task :build do
    # image is in the form of debian/buster
    raise "ENV['image'] can't be #{ENV['image'].inspect}" unless ENV['image']

    bash "docker build . -f docker/#{ENV['image'].split('/').first}/Dockerfile -t lkp-tests/#{ENV.fetch('image', nil)} --build-arg base_image=#{ENV['image'].sub('/', ':')}"
  end
end
