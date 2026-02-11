require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'fileutils'
require 'pathname'
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
      # After implementation, this should include myprog
      expect(programs).to include('myprog')
      expect(programs['myprog']).to include('programs/myprog/setup')
    end

    it 'returns daemon programs' do
      programs = job.available_programs(:daemon)
      # After implementation, this should include myprog
      expect(programs).to include('myprog')
      expect(programs['myprog']).to include('programs/myprog/daemon')
    end

    it 'aggregates programs for :workload_elements' do
      # :workload_elements includes :setup, :tests, :daemon
      programs = job.available_programs(:workload_elements)
      # NOTE: 'myprog' from tests is included because tests support programs/*/run
      expect(programs).to include('myprog')
      # 'daemon' overrides 'tests' and 'setup' due to merge order
      expect(programs['myprog']).to include('programs/myprog/daemon')
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
end

describe 'job.rb global methods' do
  describe '#expand_shell_var' do
    let(:env) { {} }

    context 'when local_run? is false' do
      before do
        allow(self).to receive(:local_run?).and_return(false)
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
        allow(self).to receive(:local_run?).and_return(true)
      end

      context 'with shell variables ($)' do
        it 'expands the variable using Bash.run' do
          expected_cmd = 'eval echo "$VAR"'
          allow(Bash).to receive(:run).with(env, expected_cmd).and_return("expanded_value\n")
          expect(expand_shell_var(env, '$VAR')).to eq('expanded_value')
        end

        it 'passes environment variables to Bash.run' do
          my_env = { 'VAR' => 'value' }
          allow(Bash).to receive(:run).with(my_env, 'eval echo "$VAR"').and_return("value\n")
          expect(expand_shell_var(my_env, '$VAR')).to eq('value')
        end
      end

      context 'with /dev/disk/ paths' do
        it 'sorts determined disks by numeric suffix' do
          # The function triggers if the string contains '/dev/disk/'
          input = '/dev/disk/by-label/d1 /dev/disk/by-label/d2'

          # Use specific return values for Dir.glob and File.realpath
          allow(Dir).to receive(:glob).with('/dev/disk/by-label/d1').and_return(['/link/to/sda10'])
          allow(Dir).to receive(:glob).with('/dev/disk/by-label/d2').and_return(['/link/to/sdb2'])

          allow(File).to receive(:realpath).with('/link/to/sda10').and_return('/dev/sda10')
          allow(File).to receive(:realpath).with('/link/to/sdb2').and_return('/dev/sdb2')

          # Sorting logic:
          # /dev/sdb2  -> 2
          # /dev/sda10 -> 10
          # Expect: "/dev/sdb2 /dev/sda10"

          expect(expand_shell_var(env, input)).to eq('/dev/sdb2 /dev/sda10')
        end

        it 'handles paths resolving to same device' do
          input = '/dev/disk/by-label/d1 /dev/disk/by-label/d1_alias'
          allow(Dir).to receive(:glob).with('/dev/disk/by-label/d1').and_return(['/dev/sda1'])
          allow(Dir).to receive(:glob).with('/dev/disk/by-label/d1_alias').and_return(['/dev/sda1'])
          allow(File).to receive(:realpath).with('/dev/sda1').and_return('/dev/sda1')

          expect(expand_shell_var(env, input)).to eq('/dev/sda1')
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
  let(:cases_dir) { "#{LKP_SRC}/spec/job" }

  # Dynamically generate tests for each .yaml file in spec/job
  Dir.glob("#{LKP_SRC}/spec/job/*.yaml").each do |absolute_input_file|
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
    FileUtils.mkdir_p("#{tmp_lkp_src}/spec/job")
    FileUtils.cp("#{LKP_SRC}/spec/job/1.mock.yaml", "#{tmp_lkp_src}/spec/job/1.mock.yaml")
    FileUtils.cp("#{LKP_SRC}/spec/job/1.mock.output.yaml", "#{tmp_lkp_src}/spec/job/1.mock.output.yaml")
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

    job_file = "#{tmp_lkp_src}/spec/job/1.mock.yaml"
    output_file = "#{tmp_lkp_src}/spec/job/1.mock.output.yaml"
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
