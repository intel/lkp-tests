require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require "#{LKP_SRC}/lib/job"
require "#{LKP_SRC}/lib/bash"

describe 'filter/disk' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('filter-disk-spec-rb-')
    @tmp_dir.add_permission

    @test_yaml_file = "#{@tmp_dir.to_s}/test.yaml".freeze
  end

  after(:all) do
    @tmp_dir.cleanup!
  end

  def generate_job(contents = { 'testcase' => 'testcase' })
    job_file = @test_yaml_file
  
    File.open(job_file, 'w') do |f|
      f.write(contents.to_yaml)
    end
  
    Job.open(job_file)
  end

  context 'when do not need disk' do
    it 'does not filter the job' do
      job = generate_job({ 'testcase' => 'testcase' })
      job.expand_params
    end
  end

  context 'when disk: 1HDD, nr_hdd_partitions: 1' do
    it 'does not filter the job' do
      job = generate_job({ 'testcase' => 'testcase', 'nr_hdd_partitions' => '1', 'disk' => '1HDD' })
      job.expand_params
    end
  end

  context 'when disk: 4HDD, nr_hdd_partitions: 1' do
    it 'filter the job' do
      job = generate_job({ 'testcase' => 'testcase', 'nr_hdd_partitions' => '1', 'disk' => '4HDD' })
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end

  context 'when disk: 1HDD, do not have hdd_partition' do
    it 'filter the job' do
      job = generate_job({ 'testcase' => 'testcase', 'disk' => '1HDD' })
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end
end
