require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/job"

describe 'filter/nr_threads' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('filter-need-kconfig-spec-')
    @tmp_dir.add_permission
    @test_yaml_file = @tmp_dir.path('test.yaml')
  end

  after(:all) do
    @tmp_dir.clean!
  end

  def generate_job(contents)
    File.write(@test_yaml_file, contents.to_yaml)
    Job.open(@test_yaml_file)
  end

  context 'when nr_threads is defined in top level with valid value' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase', 'nr_threads' => 1)
      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when nr_threads is defined in top level with invalid value' do
    it 'filters the job' do
      job = generate_job('testcase' => 'testcase', 'nr_threads' => 0)
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end

  context 'when nr_threads is defined in second level with valid value' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase', 'sleep' => { 'nr_threads' => 1 })
      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when nr_threads is defined in second level with invalid value' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase', 'sleep' => { 'nr_threads' => 0 })
      expect { job.expand_params }.not_to raise_error
    end
  end
end
