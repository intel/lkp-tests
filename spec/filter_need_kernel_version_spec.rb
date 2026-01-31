require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/job"

describe 'filter/need_kernel_version.rb' do
  before do
    @tmp_dir = LKP::TmpDir.new('filter-need-kernel-version-spec-src-')
    @tmp_dir.add_permission
  end

  after do
    @tmp_dir.clean!
  end

  def generate_context(compiler, kernel_version)
    dir = @tmp_dir.path(compiler)
    FileUtils.mkdir_p(dir)
    FileUtils.touch("#{dir}/vmlinuz")
    File.write(File.join(dir, 'context.yaml'), { 'rc_tag' => kernel_version }.to_yaml)
  end

  def generate_job(compiler, contents = "\n")
    job_file = "#{@tmp_dir}/job.yaml"

    File.open(job_file, 'w') do |f|
      f.puts contents
      f.puts "kernel: #{@tmp_dir}/#{compiler}/vmlinuz"
    end

    # Job.open can filter comments (e.g. # support kernel xxx)
    Job.open(job_file)
  end

  context 'kernel is not satisfied' do
    { 'v4.16' => 'gcc', 'v5.11' => 'clang' }.each do |version, compiler|
      it "filters the job built with #{compiler}" do
        generate_context(compiler, version)
        job = generate_job compiler, <<-EOF
need_kernel_version:
- '>= v4.16.1, gcc'
- '>= v5.12, clang'
        EOF

        expect { job.expand_params }.to raise_error Job::ParamError
      end
    end
  end

  context 'kernel is satisfied' do
    { 'v5.0' => 'gcc', 'v5.12.112' => 'clang' }.each do |version, compiler|
      it "does not filters the job built with #{compiler}" do
        generate_context(compiler, version)
        job = generate_job compiler, <<-EOF
need_kernel_version:
- '>= v4.17, gcc'
- '>= v5.12.112, clang'
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end
  end

  context 'vm selftest renamed to mm selftest in v6.3-rc1' do
    { 'gcc' => 'v6.2', 'clang' => 'v6.2' }.each do |compiler, version|
      it 'filter out the job' do
        generate_context(compiler, version)
        job = generate_job compiler, <<-EOF
need_kernel_version:
- '>= v6.3-rc1, gcc'
- '>= v6.3-rc1, clang'
        EOF

        expect { job.expand_params }.to raise_error Job::ParamError
      end
    end

    { 'gcc' => 'v6.3-rc1', 'clang' => 'v6.3-rc1' }.each do |compiler, version|
      it 'does not filter out the job' do
        generate_context(compiler, version)
        job = generate_job compiler, <<-EOF
need_kernel_version:
- '>= v6.3-rc1, gcc'
- '>= v6.3-rc1, clang'
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end
  end
end
