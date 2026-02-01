require 'fileutils'
require 'shellwords'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

describe 'log_cmd' do
  let(:log_cmd) { "#{LKP_SRC}/bin/log_cmd " }

  before(:all) do
    @pwd = Dir.pwd
    @tmp_dir = LKP::TmpDir.new('log-cmd-spec-src-')
    @tmp_dir.add_permission
    ENV['TMP_RESULT_ROOT'] = @tmp_dir.to_s
    Dir.chdir(@tmp_dir.to_s)
  end

  after(:all) do
    @tmp_dir.clean!
    Dir.chdir(@pwd)
  end

  it 'creates multi dirs' do
    was_good = Bash.run("#{log_cmd}mkdir a b")
    expect(was_good).to be_truthy
    expect(Dir).to exist('a')
    expect(Dir).to exist('b')
    Dir.delete('a')
    Dir.delete('b')
  end

  it 'creates dir with space' do
    was_good = Bash.run("#{log_cmd}mkdir \"a b\"")
    expect(was_good).to be_truthy
    expect(Dir).to exist('a b')
    Dir.delete('a b')
  end

  it 'creates dir with single quote' do
    dir = '"a'
    was_good = Bash.run("#{log_cmd}mkdir #{Shellwords.escape(dir)}")
    expect(was_good).to be_truthy
    expect(Dir).to exist('"a')
    Dir.delete('"a')
  end

  it 'creates dir with space and double quotes' do
    dir = '"a b"'
    was_good = Bash.run("#{log_cmd}mkdir #{Shellwords.escape(dir)}")
    expect(was_good).to be_truthy
    expect(Dir).to exist('"a b"')
    Dir.delete('"a b"')
  end

  it 'parses echo reserve parameter' do
    was_good = Bash.run("#{log_cmd}ls -n")
    expect(was_good).to be_truthy
  end

  it 'execute built-in command' do
    was_good = Bash.run("#{log_cmd}cd .")
    expect(was_good).to be_truthy
  end
end
