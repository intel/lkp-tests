require 'rubygems'
require 'bundler/setup'
require 'rake/file_utils'
require 'rspec/core/rake_task'
require 'fileutils'
require 'rubocop/rake_task'
require 'English'
require 'term/ansicolor'

class String
  include Term::ANSIColor
end

def tool_available?(cmd)
  system("which #{cmd} >/dev/null 2>&1")
end

GIT_SCANNABLE_FILES = 'git ls-files -z --cached --others --exclude-standard -- . ":!workspace_tmp"'.freeze

# Same file set, narrowed to executables under 100k, matching the `find
# -type f -executable ! -size +100k` filter every lint task used to repeat.
def scannable_executables_cmd
  "#{GIT_SCANNABLE_FILES} | xargs -0 -I{} find \"{}\" -maxdepth 0 -type f -executable ! -size +100k 2>/dev/null"
end

desc 'Show help'
task :help do
  puts <<~EOF
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
  spec = spec.sub(/_spec$/, '')
  t.pattern = "spec/**{,/*/**}/#{spec}_spec.rb"
  t.rspec_opts = "--example '#{ENV['example']}'" if ENV['example']
end

if ENV['GENERATE_REPORTS'] == 'true'
  require 'ci/reporter/rake/rspec'
  task spec: 'ci:setup:rspec'
end

RuboCop::RakeTask.new(:rubocop) do |t|
  ruby_version = `ruby --version | grep -oE "[0-9]+\\.[0-9]+"`.chomp

  rubocop_config_file = ".rubocop.#{ruby_version}.yml"
  rubocop_config_file = '.rubocop.yml' unless File.size?(rubocop_config_file)

  t.options = ['-D', "-c#{rubocop_config_file}"]
  t.options.unshift('-a') if ENV['fix'] == '1'
  t.patterns = [ENV['file']] if ENV['file']

  version = `rubocop --version 2>&1`.strip
  puts "rubocop (#{version}) start...".yellow
  puts "PWD = #{Dir.pwd}"
  puts "rubocop.patterns = #{t.patterns}"
  puts "rubocop.options = #{t.options}"
end

desc 'Run syntax check'
task :syntax do
  puts 'syntax start...'.yellow
  executables = `#{scannable_executables_cmd}`.split("\n").join(' ')

  sh "grep -s -l '^#!/.*ruby$' #{executables} | xargs -P$(nproc) -n1 ruby -c >/dev/null", verbose: false do |ok, res|
    exit res.exitstatus unless ok
  end

  sh "grep -s -l '^#!/.*bash$' #{executables} | xargs -P$(nproc) -n1 bash -n", verbose: false do |ok, res|
    exit res.exitstatus unless ok
  end

  sh "grep -s -l '^#!/bin/sh$' #{executables} | xargs -P$(nproc) -n1 dash -n", verbose: false do |ok, res|
    exit res.exitstatus unless ok
  end

  puts 'syntax OK'.green
end

desc 'Run shfmt'
task :shfmt do
  unless tool_available?('shfmt')
    puts 'shfmt not installed, skipping'.yellow
    next
  end

  executables = if ENV['file']
                  ENV['file']
                else
                  dir = ENV['dir'] || '.'
                  find_opts = '-type f -executable ' \
                              '! -path "*/kbuild/kbuild.sh" ' \
                              '! -path "*/node_modules/*" ' \
                              '! -path "*/sbin/makepkg" ' \
                              '! -path "*/sbin/pacman-LKP" ' \
                              '! -path "*/workspace_tmp/*" ' \
                              '! -path "*/.claude/worktrees/*" ' \
                              '! -path "./.git*" ' \
                              '! -path "./vendor*" ' \
                              '! -size +100k'
                  `find #{dir} #{find_opts} | xargs -P$(nproc) grep -s -l -e '^#!/.*bash$' -e '^#!/bin/sh$'`.split("\n").join(' ')
                end

  version = `shfmt --version 2>&1`.strip.delete_prefix('v')
  puts "shfmt (#{version}) start...".yellow

  mode_flag = ENV['fix'] == '1' ? '-w' : '-d'
  sh "shfmt #{mode_flag} -ln bash -i 0 -fn #{executables}", verbose: false do |ok, res|
    if ok
      puts "shfmt (#{version}) OK".green
    else
      exit res.exitstatus
    end
  end
end

desc 'Run shellcode (shellcheck and shfmt)'
task shellcode: %i[shellcheck shfmt]

desc 'Run shellcheck'
task :shellcheck do
  unless tool_available?('shellcheck')
    puts 'shellcheck not installed, skipping'.yellow
    next
  end

  executables = ENV['file'] || `#{scannable_executables_cmd} | xargs -P$(nproc) grep -s -l -e '^#!/.*bash$' -e '^#!/bin/sh$'`.split("\n").join(' ')

  format = ENV['format'] || 'tty'

  base_cmd = "shellcheck -S warning -f #{format}"
  base_cmd += " -i #{ENV['code']}" if ENV['code']

  version = `shellcheck --version 2>&1`.match(/^version: (\S+)/)&.captures&.first || '?'
  puts "shellcheck (#{version}) start...".yellow

  sh "#{base_cmd} #{executables}", verbose: false do |ok, res|
    if ok
      puts "shellcheck (#{version}) OK".green
    else
      exit res.exitstatus
    end
  end
end

desc 'Run yamllint'
task :yamllint do
  unless tool_available?('yamllint')
    puts 'yamllint not installed, skipping'.yellow
    next
  end

  version = `yamllint --version 2>&1`.strip.split.last
  puts "yamllint (#{version}) start...".yellow

  sh 'yamllint', '--strict', '--format=auto', '.', verbose: false do |ok, res|
    if ok
      puts "yamllint (#{version}) OK".green
    else
      exit res.exitstatus
    end
  end
end

desc 'Run ruff'
task :ruff do
  unless tool_available?('ruff')
    puts 'ruff not installed, skipping'.yellow
    next
  end

  ENV['RUFF_CACHE_DIR'] ||= '/tmp/.ruff_cache'
  version = `python3 -m ruff --version 2>&1`.strip.split.last
  puts "ruff (#{version}) start...".yellow

  fix_flag = ENV['fix'] == '1' ? '--fix' : ''
  format_flag = ENV['fix'] == '1' ? '' : '--check'
  sh "python3 -m ruff check #{fix_flag} #{ENV['file'] || '.'} && python3 -m ruff format #{format_flag} #{ENV['file'] || '.'}", verbose: false do |ok, res|
    if ok
      puts "ruff (#{version}) OK".green
    else
      exit res.exitstatus
    end
  end
end

desc 'Run pylint'
task :pylint do
  unless tool_available?('pylint')
    puts 'pylint not installed, skipping'.yellow
    next
  end

  version = `pylint --version 2>&1`.split[1]
  puts "pylint (#{version}) start...".yellow

  sh "pylint --recursive y #{ENV['file'] || '.'}", verbose: false do |ok, res|
    if ok
      puts "pylint (#{version}) OK".green
    else
      exit res.exitstatus
    end
  end
end

desc 'Run code check'
task code: %i[syntax yamllint shellcode rubocop ruff pylint]

namespace :docker do
  desc 'Build docker image'
  task :build do
    # image is in the form of debian/buster
    raise "ENV['image'] can't be #{ENV['image'].inspect}" unless ENV['image']

    sh "docker build . -f docker/#{ENV['image'].split('/').first}/Dockerfile -t lkp-tests/#{ENV.fetch('image', nil)} --build-arg base_image=#{ENV['image'].sub('/', ':')}"
  end
end
