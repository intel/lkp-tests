require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/yaml"

describe 'lkp-split-job' do
  before(:all) do
    @tmp_src_dir = LKP::TmpDir.new('split-job-spec-src-')

    # Exclude local scratch directories: they are untracked, can grow large,
    # and (if they happen to contain a nested copy of the source tree) would
    # make this rsync copy itself into itself.
    exclude_opts = '--exclude .git --exclude /workspace_tmp/ --exclude /tmp/'
    Bash.run("rsync -aix #{exclude_opts} #{LKP_SRC}/ #{@tmp_src_dir}")
    Bash.run("rsync -aix --exclude .git #{LKP_SRC}/spec/fixtures/split-job/programs/ #{@tmp_src_dir}/programs/")

    Dir.chdir(@tmp_src_dir.to_s) do
      Bash.run("bash -c \"export LKP_SRC=#{@tmp_src_dir}; . #{@tmp_src_dir}/lib/host.sh; create_host_config\"")
    end
  end

  after(:all) do
    @tmp_src_dir.clean!
  end

  before do
    @tmp_dir = LKP::TmpDir.new('split-job-spec-')
  end

  after do
    @tmp_dir.clean!
  end

  def verify_split_job_output(id)
    Bash.run("LKP_SRC=#{@tmp_src_dir} #{@tmp_src_dir}/bin/lkp split-job -t lkp-tbox -o #{@tmp_dir} spec/fixtures/split-job/#{id}.yaml")

    Dir[@tmp_dir.path("#{id}-*.yaml")].each do |actual_yaml|
      Bash.run("sed -i 's|:#! programs/split-job/|#!/|g' #{actual_yaml}")

      actual = YAML.load_file(actual_yaml)
      expected = YAML.load_file("#{LKP_SRC}/spec/fixtures/split-job/#{File.basename(actual_yaml)}")

      expect(actual).to eq expected
    end
  end

  it 'split with --compatible option' do
    Dir.chdir(@tmp_src_dir.to_s) do
      Bash.run("LKP_SRC=#{@tmp_src_dir} #{@tmp_src_dir}/bin/lkp split-job --compatible -o #{@tmp_dir} spec/fixtures/split-job/compatible.yaml")
      new_yaml = 'compatible-test_1.yaml'
      # delete machine specific settings
      %w[testbox tbox_group local_run memory nr_cpu ssd_partitions hdd_partitions model].each { |s| Bash.run("sed -i '/#{s}:/d' #{@tmp_dir.path(new_yaml)}") }
      actual = YAML.load_file(@tmp_dir.path(new_yaml))
      expected = YAML.load_file("#{LKP_SRC}/spec/fixtures/split-job/#{new_yaml}")

      expect(actual).to eq expected
    end
  end

  it "split job['split-job']['test'] only" do
    verify_split_job_output(1)
  end

  it "split job['split-job']['test'] and job['split-job']['group']" do
    verify_split_job_output(2)
  end

  it "split job['fs'] only" do
    verify_split_job_output(3)
  end

  it "split job['fs2'] with symlinked program" do
    Dir.chdir(@tmp_src_dir.to_s) do
      Bash.run("mkdir -p hosts; echo 'model: Haswell' > hosts/lkp-tbox")
      verify_split_job_output('4')
      Bash.run('rm hosts/lkp-tbox')
    end

    expect(Dir[@tmp_dir.path('4-*.yaml')]).not_to be_empty
  end
end
