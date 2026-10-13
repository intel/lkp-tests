require 'spec_helper'
require 'open3'
require 'tmpdir'

# A mount from a stalled network server blocks in the kernel forever. check_mount
# must give up on such a mount after MOUNT_TIMEOUT instead of eating the whole job
# time budget, while a (possibly slow) local mount must not be killed.
describe 'lib/mount.sh check_mount' do
  let(:mount_sh) { File.join(LKP_SRC, 'lib/mount.sh') }
  # hang only when asked to mount something (no args = listing mounts)
  let(:hanging_mount) { '[ $# -gt 0 ] && exec sleep 30; exit 0' }

  # Runs check_mount under /bin/sh (lib/mount.sh is sourced by the POSIX sh
  # boot chain) with a fake `mount` first in PATH, and returns
  # [stderr, exit status, elapsed seconds].
  def run_check_mount(source, mount_timeout:, fake_mount_body:)
    Dir.mktmpdir do |dir|
      fake_mount = File.join(dir, 'mount')
      File.write(fake_mount, "#!/bin/sh\n#{fake_mount_body}\n")
      File.chmod(0o755, fake_mount)

      env = { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'LKP_SRC' => LKP_SRC, 'MOUNT_TIMEOUT' => mount_timeout.to_s }
      script = ". #{mount_sh}; check_mount #{source} #{dir}/mnt"

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _out, err, status = Open3.capture3(env, 'sh', '-c', script)
      [err, status.exitstatus, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end
  end

  it 'gives up on a hung network mount after MOUNT_TIMEOUT' do
    err, status, elapsed = run_check_mount('server:/pkg', mount_timeout: 1, fake_mount_body: hanging_mount)

    expect(status).not_to eq(0)
    expect(err).to include('timed out after 1s')
    expect(elapsed).to be < 15
  end

  it 'bounds mount.nfs the same way' do
    Dir.mktmpdir do |dir|
      fake = File.join(dir, 'mount.nfs')
      File.write(fake, "#!/bin/sh\nexec sleep 30\n")
      File.chmod(0o755, fake)

      env = { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'LKP_SRC' => LKP_SRC, 'MOUNT_TIMEOUT' => '1' }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _out, _err, status = Open3.capture3(env, 'sh', '-c', ". #{mount_sh}; mount_nfs_timeout -o vers=3 server:/result #{dir}/mnt")

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      # 137: killed by SIGKILL after MOUNT_TIMEOUT, not merely "command not found"
      expect(status.exitstatus).to eq(137)
      expect(elapsed).to be_between(1, 15)
    end
  end

  it 'succeeds on a responsive network mount' do
    _err, status, = run_check_mount('server:/pkg', mount_timeout: 1, fake_mount_body: 'exit 0')

    expect(status).to eq(0)
  end

  it 'does not bound a local mount' do
    _err, status, elapsed = run_check_mount('/dev/fake', mount_timeout: 1, fake_mount_body: '[ $# -gt 0 ] && sleep 3; exit 0')

    expect(status).to eq(0)
    expect(elapsed).to be >= 3
  end
end
