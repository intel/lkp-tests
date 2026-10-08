require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Runs the real bin/run-stats as a subprocess against a throwaway LKP_SRC whose
# bin/, sbin/, lib/ and etc/ are the real ones but whose programs/ holds fake
# programs. That lets each check in run-stats be driven through a program with
# exactly the properties it looks at (has a `run` script, parser prints
# nothing, ...) without depending on what real programs happen to exist.
describe 'bin/run-stats' do
  def make_program(name, parse_body: '', run: true)
    dir = File.join(@lkp_src, 'programs', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'parse'), "#!/bin/bash\n#{parse_body}\n")
    File.chmod(0o755, File.join(dir, 'parse'))
    File.write(File.join(dir, 'run'), "#!/bin/bash\n") if run
  end

  def last_state
    path = File.join(@result_root, 'last_state')
    File.exist?(path) ? File.read(path) : ''
  end

  # returns [stdout, stderr, exit status]
  def run_stats(program, log: "line\n", log_file: program, env: {})
    File.write(File.join(@result_root, log_file), log) if log
    out, err, status = Open3.capture3({ 'LKP_SRC' => @lkp_src, 'RESULT_ROOT' => @result_root, 'testbox' => 'real-box' }.merge(env),
                                      File.join(@lkp_src, 'bin/run-stats'), program, chdir: @tmp)
    [out, err, status.exitstatus]
  end

  around do |example|
    Dir.mktmpdir('run-stats-spec') do |tmp|
      @tmp = tmp
      @lkp_src = File.join(tmp, 'lkp-src')
      @result_root = File.join(tmp, 'result', 'testcase', 'rt')
      FileUtils.mkdir_p([File.join(@lkp_src, 'programs'), @result_root])
      %w[bin sbin lib etc].each { |dir| File.symlink(File.join(LKP_SRC, dir), File.join(@lkp_src, dir)) }
      File.write(File.join(@result_root, 'time'), "elapsed_time: 1\n")
      File.write(File.join(@result_root, 'job.yaml'), "category: benchmark\n")
      example.run
    end
  end

  describe 'a program that produces stats' do
    before { make_program('okprog', parse_body: 'echo "throughput: 5"') }

    it 'dumps them to <program>.json without warnings' do
      _out, err, status = run_stats('okprog')

      expect(status).to eq(0)
      expect(err).to be_empty
      expect(File.read(File.join(@result_root, 'okprog.json'))).to include('okprog.throughput')
      expect(last_state).to be_empty
    end

    it 'reads a compressed log and removes the uncompressed copy afterwards' do
      log = File.join(@result_root, 'okprog')
      File.write(log, "line\n")
      system('gzip', '-f', log) || raise('gzip failed')

      _out, _err, status = run_stats('okprog', log: nil)

      expect(status).to eq(0)
      expect(File.exist?(log)).to be false
      expect(File.exist?("#{log}.gz")).to be true
      expect(File.exist?(File.join(@result_root, 'okprog.json'))).to be true
    end

    it 'removes the raw log in lite mode' do
      _out, _err, status = run_stats('okprog', env: { 'lite_mode' => '1' })

      expect(status).to eq(0)
      expect(File.exist?(File.join(@result_root, 'okprog'))).to be false
    end

    it 'keeps the raw log outside lite mode' do
      run_stats('okprog')

      expect(File.exist?(File.join(@result_root, 'okprog'))).to be true
    end
  end

  describe 'an empty or unusable log' do
    before { make_program('okprog', parse_body: 'echo "throughput: 5"') }

    it 'exits quietly and writes no stats when the log is empty' do
      _out, err, status = run_stats('okprog', log: '')

      expect(status).to eq(0)
      expect(err).to be_empty
      expect(File.exist?(File.join(@result_root, 'okprog.json'))).to be false
    end

    it 'skips a log containing NUL bytes with a warning' do
      _out, err, status = run_stats('okprog', log: "bin\0ary\n")

      expect(status).to eq(0)
      expect(err).to include('okprog: skip binary file')
      expect(File.exist?(File.join(@result_root, 'okprog.json'))).to be false
    end
  end

  describe 'last_state driven exits' do
    before { make_program('okprog', parse_body: 'echo "throughput: 5"') }

    it 'fails the rt when the job exited due to die' do
      File.write(File.join(@result_root, 'last_state'), "test.locktorture.exit_code.99: 1\n")

      _out, err, status = run_stats('okprog')

      expect(status).to eq(1)
      expect(err).to include('job exited due to die')
    end

    it 'fails the rt when the initrd could not be fetched' do
      File.write(File.join(@result_root, 'last_state'), "wget_initrd_fail: 1\n")

      _out, err, status = run_stats('okprog')

      expect(status).to eq(1)
      expect(err).to include('wget_initrd_fail')
    end

    it 'records soft_timeout once when the soft_timeout marker exists' do
      File.write(File.join(@result_root, 'soft_timeout'), '')

      2.times { run_stats('okprog') }

      expect(last_state.scan('soft_timeout: 1').size).to eq(1)
    end
  end

  describe 'a parser that fails' do
    before { make_program('badprog', parse_body: 'exit 3') }

    it 'fails the rt when nothing explains the failure' do
      _out, err, status = run_stats('badprog')

      expect(status).to eq(1)
      expect(err).to include('failed to stat badprog')
    end

    it 'carries on when the job hit a soft_timeout, which can truncate the output' do
      File.write(File.join(@result_root, 'last_state'), "soft_timeout: 1\n")

      _out, err, status = run_stats('badprog')

      expect(status).to eq(0)
      expect(err).to include('failed to stat badprog')
    end
  end

  describe 'a parser that prints nothing' do
    # With a run script, the missing stats are recorded in last_state as an
    # incomplete run; that non-empty last_state then suppresses the separate
    # empty-stats warning, so a program gets one or the other, never both.
    context 'when the program has a run script' do
      before { make_program('emptyprog') }

      it 'marks the run incomplete' do
        _out, err, status = run_stats('emptyprog')

        expect(status).to eq(0)
        expect(last_state).to include('# missing emptyprog', 'is_incomplete_run: 1')
        expect(err).not_to include('empty stats')
      end
    end

    context 'when the program has no run script' do
      before { make_program('emptyprog', run: false) }

      it 'only warns about empty stats' do
        _out, err, = run_stats('emptyprog')

        expect(last_state).to be_empty
        expect(err).to include('emptyprog: empty stats')
      end

      it 'does not warn on a vm testbox' do
        _out, err, = run_stats('emptyprog', env: { 'testbox' => 'vm-snb-1' })

        expect(err).not_to include('empty stats')
      end

      it 'does not warn when the job recorded a last_state' do
        File.write(File.join(@result_root, 'last_state'), "running: 1\n")

        _out, err, = run_stats('emptyprog')

        expect(err).not_to include('empty stats')
      end

      it 'does not warn without a time record' do
        FileUtils.rm_f(File.join(@result_root, 'time'))

        _out, err, = run_stats('emptyprog')

        expect(err).not_to include('empty stats')
      end
    end

    # These programs report only problems, so an empty result is the healthy
    # outcome: it must be neither flagged incomplete nor warned about, whether
    # or not they ship a run script. They are exempted by the programs' own
    # catch-all classifier rules, not by a hard-coded name list.
    %w[kmsg last_state stderr].each do |program|
      [true, false].each do |with_run|
        context "when it is #{program}, which only reports problems, #{with_run ? 'with' : 'without'} a run script" do
          before { make_program(program, run: with_run) }

          it 'is neither marked incomplete nor warned about' do
            _out, err, status = run_stats(program)

            expect(status).to eq(0)
            expect(last_state).not_to include('is_incomplete_run')
            expect(err).not_to include('empty stats')
          end
        end
      end
    end

    # The exemption comes from the classifier's own catch-all rule for the
    # program, not from a list of names in run-stats: a program gains it by
    # getting an `<program>: .+` rule in etc/stat-classifier.yml.
    context 'when a catch-all rule for the program is added to etc/stat-classifier.yml' do
      before do
        make_program('quietprog')
        etc_dir = File.join(@tmp, 'etc')
        FileUtils.mkdir_p(etc_dir)
        Dir.children(File.join(LKP_SRC, 'etc')).each do |entry|
          File.symlink(File.join(LKP_SRC, 'etc', entry), File.join(etc_dir, entry)) unless entry == 'stat-classifier.yml'
        end
        File.write(File.join(etc_dir, 'stat-classifier.yml'),
                   File.read(File.join(LKP_SRC, 'etc/stat-classifier.yml')).sub(/^fail:\n/, "fail:\n  quietprog: .+\n"))
        FileUtils.rm_f(File.join(@lkp_src, 'etc'))
        File.symlink(etc_dir, File.join(@lkp_src, 'etc'))
      end

      it 'is neither marked incomplete nor warned about' do
        _out, err, status = run_stats('quietprog')

        expect(status).to eq(0)
        expect(last_state).not_to include('is_incomplete_run')
        expect(err).not_to include('empty stats')
      end
    end

    # Programs that have rules for specific stats only are not exempt: an empty
    # parse means the run did not produce its results.
    %w[kselftests locktorture rcutorture avocado].each do |program|
      context "when it is #{program}, which has rules for specific stats only" do
        it 'is marked incomplete when it has a run script' do
          make_program(program)

          run_stats(program)

          expect(last_state).to include('is_incomplete_run: 1')
        end

        it 'is warned about when it has no run script' do
          make_program(program, run: false)

          _out, err, = run_stats(program)

          expect(err).to include("#{program}: empty stats")
        end
      end
    end

    context 'when it is dmesg' do
      before { make_program('dmesg') }

      it 'is not marked incomplete and not warned about' do
        _out, err, = run_stats('dmesg')

        expect(last_state).not_to include('is_incomplete_run')
        expect(err).not_to include('empty stats')
      end
    end
  end
end
