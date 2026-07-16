require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/job"

describe 'filters/need_cpu_model' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('filter-need-cpu-model-spec-')
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

  context 'when do not have need_cpu_model' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase')
      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when model is in the need_cpu_model list' do
    it 'does not filter the job' do
      job = generate_job('testcase' => 'testcase', 'model' => 'Sapphire Rapids',
                         'need_cpu_model' => 'Sapphire_Rapids,Emerald_Rapids,Granite_Rapids')
      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when model is not in the need_cpu_model list' do
    it 'filters the job' do
      job = generate_job('testcase' => 'testcase', 'model' => 'Panther Lake',
                         'need_cpu_model' => 'Sapphire_Rapids,Emerald_Rapids,Granite_Rapids')
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end

  context 'when model has a numerically larger id than every listed model (regression guard)' do
    it 'still filters the job' do
      job = generate_job('testcase' => 'testcase', 'model' => 'Panther Lake',
                         'need_cpu_model' => 'Sapphire_Rapids')
      expect { redirect_to_string { job.expand_params } }.to raise_error Job::ParamError
    end
  end
end
