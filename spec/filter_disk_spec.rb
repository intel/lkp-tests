require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/job"

describe 'filter/disk' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('filter-disk-spec-rb-')
    @tmp_dir.add_permission

    @test_yaml_file = @tmp_dir.path('test.yaml').freeze
  end

  after(:all) do
    @tmp_dir.clean!
  end

  def generate_job(contents)
    File.write(@test_yaml_file, contents.to_yaml)

    Job.open(@test_yaml_file)
  end

  context 'when do not need disk' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase')
      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when disk: 1HDD, nr_hdd_partitions: 1' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase', 'nr_hdd_partitions' => '1', 'disk' => '1HDD')
      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when disk: 4HDD, nr_hdd_partitions: 1' do
    it 'filter the job' do
      job = generate_job('testcase' => 'testcase', 'nr_hdd_partitions' => '1', 'disk' => '4HDD')
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end

  context 'when disk: 1HDD, do not have hdd_partition' do
    it 'filter the job' do
      job = generate_job('testcase' => 'testcase', 'disk' => '1HDD')
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end
end
