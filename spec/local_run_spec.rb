#!/usr/bin/env ruby
require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/lkp_tmpdir"
require "#{LKP_SRC}/lib/yaml"

describe 'local run' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('local-run-spec-')
    @tmp_dir.add_permission
    @tmp_file = @tmp_dir.path('run-env-tmp.rb')
    FileUtils.cp "#{LKP_SRC}/lib/run_env.rb", @tmp_file
    s = ''
    File.open(@tmp_file, 'r') do |f|
      f.each_line { |l| s += l.gsub(/\#{LKP_SRC}\/hosts\//, "#{@tmp_dir}/") }
      f.rewind
    end
    File.write(@tmp_file, s)

    require @tmp_file
    @hostname = `hostname`.chomp
    @hostfile = @tmp_dir.path(@hostname)
  end

  def write_host_file(content)
    File.write(@hostfile, content)
  end

  after(:all) do
    @tmp_dir.clean!
  end

  describe 'local_run' do
    after do
      FileUtils.rm_f(@hostfile)
      ENV[LOCAL_RUN_ENV] = nil
    end

    it 'first run without host file or ENV' do
      expect(local_run?).to be(false)
    end

    it 'first run with host file with local_run: 1' do
      write_host_file("local_run: 1\n")
      expect(local_run?).to be(true)
    end

    it 'first run with host file with local_run: 0' do
      write_host_file("local_run: 0\n")
      expect(local_run?).to be(false)
    end

    it 'first run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      expect(local_run?).to be(false)
    end

    it 'second run without host file or ENV' do
      local_run?
      expect(local_run?).to be(false)
    end

    it 'second run with host file with local_run: 1' do
      write_host_file("local_run: 1\n")
      local_run?
      expect(local_run?).to be(true)
    end

    it 'second run with host file with local_run: 0' do
      write_host_file("local_run: 0\n")
      local_run?
      expect(local_run?).to be(false)
    end

    it 'second run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      local_run?
      expect(local_run?).to be(false)
    end
  end

  describe 'local_run ENV 0' do
    before do
      ENV[LOCAL_RUN_ENV] = '0'
    end

    after do
      FileUtils.rm_f(@hostfile)
      ENV[LOCAL_RUN_ENV] = nil
    end

    it 'first run without host file' do
      expect(local_run?).to be(false)
    end

    it 'first run with host file of local_run: 1' do
      write_host_file("local_run: 1\n")
      expect(local_run?).to be(false)
    end

    it 'first run with host file of local_run: 0' do
      write_host_file("local_run: 0\n")
      expect(local_run?).to be(false)
    end

    it 'first run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      expect(local_run?).to be(false)
    end
  end

  describe 'local_run ENV 1' do
    before do
      ENV[LOCAL_RUN_ENV] = '1'
    end

    after do
      FileUtils.rm_f @hostfile
      ENV[LOCAL_RUN_ENV] = nil
    end

    it 'first run without host file' do
      expect(local_run?).to be(true)
    end

    it 'first run with host file of local_run: 1' do
      write_host_file("local_run: 1\n")
      expect(local_run?).to be(true)
    end

    it 'first run with host file of local_run: 0' do
      write_host_file("local_run: 0\n")
      expect(local_run?).to be(true)
    end

    it 'first run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      expect(local_run?).to be(true)
    end
  end
end
