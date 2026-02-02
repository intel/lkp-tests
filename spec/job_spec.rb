require 'spec_helper'
require "#{LKP_SRC}/lib/job"

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
