#!/usr/bin/env ruby
require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/lkp_tmpdir"

describe 'local run' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('local-run-spec-')
    @tmp_dir.add_permission
    @tmp_file = @tmp_dir.path('run-env-tmp.rb')
    FileUtils.cp "#{LKP_SRC}/lib/run_env.rb", @tmp_file
    s = ''
    File.open(@tmp_file, 'r') do |f|
      f.each_line { |l| s += l.gsub(/\#{LKP_SRC}\/hosts\//, "#{@tmp_dir}/") } # rubocop:disable Lint/InterpolationCheck
      f.rewind
    end
    File.open(@tmp_file, 'w') { |f| f.write s }

    require @tmp_file
    @hostname = `hostname`.chomp
    @hostfile = @tmp_dir.path(@hostname)
  end

  def write_host_file(content)
    File.open(@hostfile, 'w') { |file| file.write(content) }
  end

  describe 'local_run' do
    it 'first run without host file or ENV' do
      expect(local_run?).to eq(false)
    end

    it 'first run with host file with local_run: 1' do
      write_host_file("local_run: 1\n")
      expect(local_run?).to eq(true)
    end

    it 'first run with host file with local_run: 0' do
      write_host_file("local_run: 0\n")
      expect(local_run?).to eq(false)
    end

    it 'first run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      local_run?
      expect(local_run?).to eq(false)
    end

    it 'second run without host file or ENV' do
      local_run?
      expect(local_run?).to eq(false)
    end

    it 'second run with host file with local_run: 1' do
      write_host_file("local_run: 1\n")
      local_run?
      expect(local_run?).to eq(true)
    end

    it 'second run with host file with local_run: 0' do
      write_host_file("local_run: 0\n")
      local_run?
      expect(local_run?).to eq(false)
    end

    it 'second run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      local_run?
      expect(local_run?).to eq(false)
    end

    after(:each) do
      FileUtils.rm_f(@hostfile)
      ENV[LOCAL_RUN_ENV] = nil
    end
  end

  describe 'local_run ENV 0' do
    before(:each) do
      ENV[LOCAL_RUN_ENV] = '0'
    end

    it 'first run without host file' do
      expect(local_run?).to eq(false)
    end

    it 'first run with host file of local_run: 1' do
      write_host_file("local_run: 1\n")
      expect(local_run?).to eq(false)
    end

    it 'first run with host file of local_run: 0' do
      write_host_file("local_run: 0\n")
      expect(local_run?).to eq(false)
    end

    it 'first run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      expect(local_run?).to eq(false)
    end

    after(:each) do
      FileUtils.rm_f(@hostfile)
      ENV[LOCAL_RUN_ENV] = nil
    end
  end

  describe 'local_run ENV 1' do
    before(:each) do
      ENV[LOCAL_RUN_ENV] = '1'
    end

    it 'first run without host file' do
      expect(local_run?).to eq(true)
    end

    it 'first run with host file of local_run: 1' do
      write_host_file("local_run: 1\n")
      expect(local_run?).to eq(true)
    end

    it 'first run with host file of local_run: 0' do
      write_host_file("local_run: 0\n")
      expect(local_run?).to eq(true)
    end

    it 'first run with host file without local_run' do
      write_host_file("hdd_partitions: \nssd_partitions: \n")
      expect(local_run?).to eq(true)
    end

    after(:each) do
      FileUtils.rm_f @hostfile
      ENV[LOCAL_RUN_ENV] = nil
    end
  end

  after(:all) do
    @tmp_dir.cleanup!
  end
end