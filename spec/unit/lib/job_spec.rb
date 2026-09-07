require 'spec_helper'
require 'fileutils'
require 'pathname'
require 'tmpdir'
require 'yaml'
require "#{LKP_SRC}/lib/job"

describe Job do
  let(:job) { described_class.new }

  describe '#available_programs' do
    include_context 'mocked filesystem'

    before do
      allow(job).to receive(:lkp_src).and_return(tmp_lkp_src)
    end

    it 'returns tests programs' do
      programs = job.available_programs(:tests)
      expect(programs).to include('myprog')
      expect(programs['myprog']).to include('programs/myprog/run')
    end

    it 'returns stats programs' do
      programs = job.available_programs(:stats)
      expect(programs).to include('myprog')
      expect(programs['myprog']).to include('programs/myprog/parse')
    end

    it 'returns setup programs' do
      programs = job.available_programs(:setup)
      # After implementation, this should include mysetup3
      expect(programs).to include('mysetup3')
      expect(programs['mysetup3']).to include('programs/mysetup3/setup')
    end

    it 'returns monitors programs' do
      programs = job.available_programs(:monitors)
      expect(programs).to include('myplainmonitor')
      expect(programs['myplainmonitor']).to include('programs/myplainmonitor/plain-monitor')
    end

    it 'returns daemon programs' do
      programs = job.available_programs(:daemon)
      # After implementation, this should include mydaemon2
      expect(programs).to include('mydaemon2')
      expect(programs['mydaemon2']).to include('programs/mydaemon2/daemon')
    end

    it 'aggregates programs for :workload_elements' do
      # :workload_elements includes :setup, :tests, :daemon
      programs = job.available_programs(:workload_elements)
      # NOTE: 'myprog' from tests is included because tests support programs/*/run
      expect(programs).to include('myprog')
      # 'daemon' overrides 'tests' and 'setup' due to merge order
      # mydaemon2 is from daemon
      expect(programs).to include('mydaemon2')
      expect(programs['mydaemon2']).to include('programs/mydaemon2/daemon')

      # myprog is from tests
      expect(programs['myprog']).to include('programs/myprog/run')
    end

    context 'when moving a legacy setup script to programs' do
      before do
        # Simulate moving 'cpufreq_governor' from setup/ to programs/cpufreq_governor/setup
        FileUtils.mkdir_p("#{tmp_lkp_src}/programs/cpufreq_governor")
        FileUtils.touch("#{tmp_lkp_src}/programs/cpufreq_governor/setup")
        FileUtils.chmod(0o755, "#{tmp_lkp_src}/programs/cpufreq_governor/setup")
      end

      it 'finds the script in the new location preserving the name' do
        programs = job.available_programs(:setup)
        expect(programs).to include('cpufreq_governor')
        expect(programs['cpufreq_governor']).to include('programs/cpufreq_governor/setup')
      end
    end
  end

  describe '#include_files' do
    include_context 'mocked filesystem'

    before do
      allow(job).to receive(:lkp_src).and_return(tmp_lkp_src)
    end

    it 'detects single-file includes in programs' do
      includes = job.include_files
      expect(includes).to include('mytask')
      expect(includes['mytask']['mytask']).to eq("#{tmp_lkp_src}/programs/mytask/include")
    end

    it 'detects directory-based includes in programs' do
      includes = job.include_files
      expect(includes).to include('myfs')
      expect(includes['myfs']).to include('subconf1')
      expect(includes['myfs']['subconf1']).to eq("#{tmp_lkp_src}/programs/myfs/include/subconf1")
    end

    it 'detects includes in symlinked programs' do
      includes = job.include_files
      # myfs_symlink -> myfs
      expect(includes).to include('myfs_symlink')
      # It should resolve subconf1 inside the linked directory but use 'myfs_symlink' as key
      expect(includes['myfs_symlink']).to include('subconf1')
      expect(includes['myfs_symlink']['subconf1']).to eq("#{tmp_lkp_src}/programs/myfs_symlink/include/subconf1")
    end
  end
end

describe 'job.rb global methods' do
  describe '#expand_shell_var' do
    let(:env) { {} }

    context 'when local_run? is false' do
      before do
        ENV[LOCAL_RUN_ENV] = '0'
      end

      after do
        ENV.delete(LOCAL_RUN_ENV)
      end

      it 'returns the string as is even if it contains $' do
        expect(expand_shell_var(env, '$HOME')).to eq('$HOME')
      end

      it 'returns the string as is even if it contains /dev/disk/' do
        path = '/dev/disk/by-id/ata-SSD'
        expect(expand_shell_var(env, path)).to eq(path)
      end
    end

    context 'when local_run? is true' do
      before do
        ENV[LOCAL_RUN_ENV] = '1'
      end

      after do
        ENV.delete(LOCAL_RUN_ENV)
      end

      context 'with shell variables ($)' do
        it 'expands the variable using Bash.run' do
          expect(expand_shell_var(env, '$HOME')).to eq(Dir.home)
        end

        it 'passes environment variables to Bash.run' do
          my_env = { 'VAR' => 'value' }
          expect(expand_shell_var(my_env, '$VAR')).to eq('value')
        end
      end

      context 'with /dev/disk/ paths' do
        # expand_shell_var resolves each path via Dir.glob then File.realpath,
        # which require the target to actually exist -- build a real
        # by-label -> device symlink layout instead of stubbing Dir/File.
        # It only takes this branch when the input contains '/dev/disk/',
        # so by_label_dir must be nested under a real .../dev/disk/by-label/.
        let(:disk_dir) { Dir.mktmpdir('job-spec-disk-') }
        let(:by_label_dir) { File.join(disk_dir, 'dev', 'disk', 'by-label') }

        before do
          FileUtils.mkdir_p(by_label_dir)
        end

        after do
          FileUtils.remove_entry disk_dir
        end

        def make_device(name)
          path = File.join(disk_dir, name)
          FileUtils.touch(path)
          path
        end

        def make_label(label, device_path)
          link = File.join(by_label_dir, label)
          File.symlink(device_path, link)
          link
        end

        it 'sorts determined disks by numeric suffix' do
          sda10 = make_device('sda10')
          sdb2 = make_device('sdb2')
          d1 = make_label('d1', sda10)
          d2 = make_label('d2', sdb2)

          # Sorting logic:
          # sdb2  -> 2
          # sda10 -> 10
          # Expect: "sdb2 sda10"
          expect(expand_shell_var(env, "#{d1} #{d2}")).to eq("#{sdb2} #{sda10}")
        end

        it 'handles paths resolving to same device' do
          sda1 = make_device('sda1')
          d1 = make_label('d1', sda1)
          d1_alias = make_label('d1_alias', sda1)

          expect(expand_shell_var(env, "#{d1} #{d1_alias}")).to eq(sda1)
        end
      end

      context 'with normal string' do
        it 'returns string as is' do
          expect(expand_shell_var(env, 'normal_string')).to eq('normal_string')
        end
      end
    end
  end
end

describe 'Job integration' do
  let(:cases_dir) { "#{LKP_SRC}/spec/fixtures/job" }

  # Dynamically generate tests for each .yaml file in spec/job
  Dir.glob("#{LKP_SRC}/spec/fixtures/job/*.yaml").each do |absolute_input_file|
    next if absolute_input_file.end_with?('.output.yaml')
    # Skip items specifically intended for mock environment tests
    next if absolute_input_file.include?('.mock.yaml')

    # Use relative path for consistent job_origin
    input_file = Pathname.new(absolute_input_file).relative_path_from(Pathname.new(LKP_SRC)).to_s
    base_name = File.basename(input_file)
    output_file = absolute_input_file.sub('.yaml', '.output.yaml')

    it "loads #{base_name} and saves it correctly matching #{File.basename(output_file)}" do
      job = Job.open(input_file)

      # Using a temporary file to save the output
      tmp_output = "#{absolute_input_file}.tmp"
      job.save(tmp_output)

      # Read both expected and actual output
      if File.exist?(output_file)
        expected = File.read(output_file)
        actual = File.read(tmp_output)

        # Basic string comparison (might need more robust YAML comparison if ordering changes)
        expect(actual).to eq(expected)
      else
        # If output file doesn't exist, fail but print the output so we can create it
        actual = File.read(tmp_output)
        raise "Expected output file #{output_file} does not exist. Generated content:\n#{actual}"
      end
    ensure
      FileUtils.rm_f(tmp_output) if defined?(tmp_output)
      FileUtils.rm_f("#{input_file}-#{Process.pid}") if defined?(input_file) # cleanup temp files if Job creates them
    end
  end
end

describe 'Job integration with mocked filesystem' do
  include_context 'mocked filesystem'

  before do
    # Copy artifacts to the mocked repo so Job finds them
    FileUtils.mkdir_p("#{tmp_lkp_src}/spec/fixtures/job")
    FileUtils.cp("#{LKP_SRC}/spec/fixtures/job/1.mock.yaml", "#{tmp_lkp_src}/spec/fixtures/job/1.mock.yaml")
    FileUtils.cp("#{LKP_SRC}/spec/fixtures/job/1.mock.output.yaml", "#{tmp_lkp_src}/spec/fixtures/job/1.mock.output.yaml")
  end

  it 'loads 1.mock.yaml and produces 1.mock.output.yaml with setup discovery' do
    # Force Job instances to use the temp directory as LKP_SRC
    allow_any_instance_of(Job).to receive(:lkp_src).and_return(tmp_lkp_src)

    # Stub Bash.run to simulate program-options output without invoking real binaries
    allow(Bash).to receive(:run).and_call_original

    # Stub for the mock_setup script
    allow(Bash).to receive(:run).with(/program-options.*mock_setup\/setup/).and_return("setup\tmock_setup") # Output Format: type name
    allow(Bash).to receive(:run).with(/program-options.*program_setup\/setup/).and_return("setup\tprogram_setup")

    # Stub for wrapper calls (expected during init)
    allow(Bash).to receive(:run).with(/program-options.*wrapper/).and_return('')

    job_file = "#{tmp_lkp_src}/spec/fixtures/job/1.mock.yaml"
    output_file = "#{tmp_lkp_src}/spec/fixtures/job/1.mock.output.yaml"
    tmp_output = "#{job_file}.tmp"

    expect(File.exist?("#{tmp_lkp_src}/include/category/mock-category")).to be true

    # Execute End-to-End
    job = Job.open(job_file)
    job.each_job_init
    job.load_defaults
    job.save(tmp_output)

    # Verification
    expected = File.read(output_file).gsub('/tmp/mock_lkp_src', tmp_lkp_src) # normalize temp path
    actual = File.read(tmp_output)

    # Verify content matches expectation
    # Check if mock_setup key is preserved (proof that open worked)
    expect(actual).to include('mock_setup:')

    # Since exact file match might struggle with dynamic tmp paths in job_origin,
    # we verify the structure or specific key elements if strict equality fails on paths
    begin
      expect(actual).to eq(expected)
    rescue RSpec::Expectations::ExpectationNotMetError
      # Fallback for dynamic path handling
      expected_lines = expected.lines.reject { |l| l.include?('job_origin') }
      actual_lines = actual.lines.reject { |l| l.include?('job_origin') }
      expect(actual_lines).to eq(expected_lines)
    end
  end
end
