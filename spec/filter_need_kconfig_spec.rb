require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/job"
require "#{LKP_SRC}/lib/kernel_tag"

describe 'filters/need_kconfig.rb' do
  before do
    @tmp_dir = LKP::TmpDir.new('filter-need-kconfig-spec-src-')
    @tmp_dir.add_permission

    File.write(@tmp_dir.path('context.yaml'), { 'rc_tag' => 'v5.0-rc1', 'kconfig' => 'i386-randconfig' }.to_yaml)

    File.write(@tmp_dir.path('.config'), "CONFIG_X=y\nCONFIG_Y=200\nCONFIG_Z1=m\nCONFIG_Z2=y\nCONFIG_H=0x1000000")

    allow(KernelTag).to receive(:kconfigs_yaml).and_return(@tmp_dir.path('kconfigs.yaml'))
  end

  after do
    @tmp_dir.clean!
  end

  def generate_kconfigs_yaml(kconfigs_kernel_versions)
    File.open(KernelTag.kconfigs_yaml, 'w') do |f|
      f.puts kconfigs_kernel_versions
    end
  end

  def generate_job(contents = "\n")
    job_file = "#{@tmp_dir}/job.yaml"

    File.open(job_file, 'w') do |f|
      f.puts contents
      f.puts "kernel: #{@tmp_dir}/vmlinuz"
    end

    # Job.open can filter comments (e.g. # support kernel xxx)
    Job.open(job_file)
  end

  context 'when X is disabled in kernel' do
    it 'filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- X: n
      EOF
      expect { job.expand_params }.to raise_error Job::ParamError
    end
  end

  context 'when X is required to be n on x86_64' do
    it 'does not filter the i386 job' do
      job = generate_job <<-EOF
need_kconfig:
- X: n, x86_64
      EOF

      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when X is required to be n on i386' do
    it 'filters the i386 job' do
      job = generate_job <<-EOF
need_kconfig:
- X: n, i386
      EOF
      expect { job.expand_params }.to raise_error Job::ParamError
    end
  end

  context 'when X is only supported on x86_64' do
    it 'does not filter the i386 job' do
      generate_kconfigs_yaml('X: x86_64')

      job = generate_job <<-EOF
need_kconfig:
- X: n, i386
      EOF

      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when X is only supported on i386' do
    context 'when X is required to be n on x86_64' do
      it 'does not filter the i386 job' do
        generate_kconfigs_yaml('X: i386')

        job = generate_job <<-EOF
need_kconfig:
- X: n, x86_64
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end
  end

  context 'when Z does not set n/m/y or version' do
    it 'does not filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- Z1
- Z2
      EOF

      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when Z does not set n/m/y' do
    it 'does not filters the job' do
      generate_kconfigs_yaml('Z1: v4.9')

      job = generate_job <<-EOF
need_kconfig:
- Z1: v4.9 # support kernel >=v4.9
      EOF

      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when X needs to set value' do
    it 'filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- X: 200
      EOF

      expect { job.expand_params }.to raise_error Job::ParamError
    end
  end

  context 'when the value of Y is the same as kconfig' do
    it 'does not filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- Y: 200
      EOF

      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when the value of Y is not the same as kconfig' do
    it 'filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- Y: 100
      EOF

      expect { job.expand_params }.to raise_error Job::ParamError
    end
  end

  context 'when syntax is wrong' do
    it 'raises syntax error' do
      job = generate_job <<-EOF
need_kconfig:
- X=y ~ '>= v5.1-rc1' # support kernel >=v5.1-rc1
      EOF

      expect { job.expand_params }.to raise_error Job::SyntaxError
    end
  end

  context 'when X is built-in in kernel' do
    context 'when kernel version meets the constraints' do
      it 'does not filter the job' do
        generate_kconfigs_yaml('X: v4.9, <= v5.0')

        job = generate_job <<-EOF
need_kconfig:
  - X: y
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end

    context 'when kernel version does not meet the constraints' do
      it 'does not filter the job' do
        generate_kconfigs_yaml('X: ">= v5.1-rc1"')

        job = generate_job <<-EOF
need_kconfig:
- X: y
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end

    context 'when kernel version limit is not defined' do
      it 'does not filter the job' do
        # old syntax with
        job = generate_job <<-EOF
need_kconfig: X=y
        EOF

        expect { job.expand_params }.not_to raise_error

        job = generate_job <<-EOF
need_kconfig: X
        EOF

        expect { job.expand_params }.not_to raise_error

        job = generate_job <<-EOF
need_kconfig:
- X: y
        EOF

        expect { job.expand_params }.not_to raise_error

        job = generate_job <<-EOF
need_kconfig:
- X
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end
  end

  context 'when Y is not built in kernel' do
    context 'when kernel version is within the range' do
      it 'filters the job' do
        generate_kconfigs_yaml('Y: <= v5.0, v4.9')

        job = generate_job <<-EOF
need_kconfig:
- Y: m
        EOF

        expect { job.expand_params }.to raise_error Job::ParamError
      end
    end

    context 'when kernel version is not within the range' do
      it 'does not filter the job' do
        generate_kconfigs_yaml('Y: v5.1-rc1, <= v5.1-rc2')

        job = generate_job <<-EOF
need_kconfig:
- Y: m
        EOF

        expect { job.expand_params }.not_to raise_error
      end
    end

    context 'when there is no kernel version constraints' do
      it 'filters the job' do
        job = generate_job <<-EOF
need_kconfig: Y=m
        EOF

        expect { job.expand_params }.to raise_error Job::ParamError
      end
    end

    context 'when Y is not defined' do
      it 'does not filter the job' do
        job = generate_job

        expect { job.expand_params }.not_to raise_error
      end
    end
  end

  context 'when H is 0xXXXX in kernel' do
    it 'does not filter the job' do
      job = generate_job <<-EOF
need_kconfig:
- H: "0x1000000"
      EOF

      expect { job.expand_params }.not_to raise_error
    end
  end

  context 'when the value of H is not the same as kconfig' do
    it 'filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- H: "0x2000000"
      EOF

      expect { job.expand_params }.to raise_error Job::ParamError
    end
  end

  context 'when H is not correct 0xXXXX in kernel' do
    it 'filters the job' do
      job = generate_job <<-EOF
need_kconfig:
- H: "0x100000g"
      EOF

      expect { job.expand_params }.to raise_error Job::SyntaxError
    end
  end
end
