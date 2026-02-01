require 'spec_helper'
require "#{LKP_SRC}/lib/bash"

describe Bash do
  describe '.run' do
    it 'runs a simple command' do
      expect(described_class.run('echo hello')).to eq('hello')
    end

    it 'runs with valid exit codes' do
      expect do
        described_class.run('false', returns: [1])
      end.not_to raise_error
    end

    it 'raises BashCallError on failure' do
      expect do
        described_class.run('false')
      end.to raise_error(Bash::BashCallError)
    end

    it 'raises BashCallError with correct status' do
      described_class.run('exit 2')
    rescue Bash::BashCallError => e
      expect(e.exitstatus).to eq(2)
    end

    it 'preserves bash functionality (<())' do
      res = described_class.run('cat <(echo ok)')
      expect(res).to eq('ok')
    end

    it 'yields result (stdout, stderr, status) to block' do
      described_class.run('echo test') do |out, _err, status|
        expect(out.chomp).to eq('test')
        expect(status).to eq(0)
      end
    end

    it 'supports dry_run mode' do
      # Should not create file
      file = '/tmp/lkp_bash_spec_dry_run'
      FileUtils.rm_f(file)

      described_class.run("touch #{file}", dry_run: true)

      expect(File).not_to exist(file)
      FileUtils.rm_f(file)
    end

    context 'with stream: true' do
      it 'streams output to block' do
        lines = []
        described_class.run('echo A; echo B', stream: true) do |line|
          lines << line
        end
        expect(lines).to include('A', 'B')
      end

      it 'uses default block (puts) if block not given' do
        expect do
          described_class.run('echo test_pipe_default', stream: true)
        end.to output(/test_pipe_default/).to_stdout
      end
    end

    context 'with verbose: true' do
      it 'prints command execution info' do
        expect do
          described_class.run('echo verbose_test', verbose: true)
        end.to output(/Running.*bash -c.*verbose_test/).to_stdout
      end
    end

    context 'environment variables' do
      before do
        ENV['LKP_TEST_ENV_VAR'] = 'present'
      end

      after do
        ENV.delete('LKP_TEST_ENV_VAR')
      end

      it 'passes environment variables' do
        out = described_class.run({ 'NEW_VAR' => 'hello' }, 'echo $NEW_VAR')
        expect(out).to eq('hello')
      end

      it 'inherits environment by default (unsetenv_others: false)' do
        out = described_class.run('echo $LKP_TEST_ENV_VAR')
        expect(out).to eq('present')
      end

      it 'clears environment when unsetenv_others: true' do
        out = described_class.run('echo $LKP_TEST_ENV_VAR', unsetenv_others: true)
        expect(out).to be_empty
      end

      it 'clears environment when unsetenv_others: true (legacy alias)' do
        out = described_class.run('echo $LKP_TEST_ENV_VAR', unsetenv_others: true)
        expect(out).to be_empty
      end

      it 'passes specific env vars even with unsetenv_others: true' do
        out = described_class.run({ 'PRESERVED' => 'yes' }, 'echo $PRESERVED', unsetenv_others: true)
        expect(out).to eq('yes')
      end
    end

    context 'with timeout' do
      it 'raises TimeoutError when command exceeds timeout' do
        expect do
          described_class.run('sleep 2', timeout: 0.1)
        end.to raise_error(Bash::TimeoutError)
      end
    end
  end
end
