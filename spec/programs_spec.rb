require 'fileutils'
require 'spec_helper'
require "#{LKP_SRC}/lib/lkp_tmpdir"
require "#{LKP_SRC}/lib/programs"

describe LKP::Programs do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('programs-spec-')
    @lkp_src = @tmp_dir.to_s

    # Setup test structure
    FileUtils.mkdir_p("#{@lkp_src}/tests")
    FileUtils.mkdir_p("#{@lkp_src}/daemon")
    FileUtils.mkdir_p("#{@lkp_src}/programs")

    # Regular test
    FileUtils.touch("#{@lkp_src}/tests/mytest")
    # Program test
    FileUtils.mkdir_p("#{@lkp_src}/programs/progtest")
    FileUtils.touch("#{@lkp_src}/programs/progtest/run")

    # Regular daemon
    FileUtils.touch("#{@lkp_src}/daemon/olddaemon")

    # Program daemon (the bug reproduction case)
    FileUtils.mkdir_p("#{@lkp_src}/programs/newdaemon")
    FileUtils.touch("#{@lkp_src}/programs/newdaemon/daemon")
  end

  before do
    stub_const('LKP_SRC', @lkp_src)
    stub_const('LKP::Programs::PROGRAMS_ROOT', File.join(@lkp_src, 'programs'))
  end

  after(:all) do
    @tmp_dir.clean!
  end

  describe '.all_tests' do
    it 'finds all tests from tests/ and programs/*/run' do
      expect(described_class.all_tests).to include('mytest', 'progtest')
    end
  end

  describe '.all_tests_and_daemons' do
    it 'finds all tests' do
      expect(described_class.all_tests_and_daemons).to include('mytest', 'progtest')
    end

    it 'finds daemons in daemon/' do
      expect(described_class.all_tests_and_daemons).to include('olddaemon')
    end

    it 'finds daemons in programs/*/daemon' do
      expect(described_class.all_tests_and_daemons).to include('newdaemon')
    end
  end
end
