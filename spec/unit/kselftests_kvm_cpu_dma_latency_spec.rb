require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# rseq_test (tools/testing/selftests/kvm) migrates a task across CPUs 100000
# times while another thread counts successful KVM_RUNs, and asserts that more
# than half of the migrations completed a KVM_RUN. On a host whose CPUs sit in
# deep idle states, the wakeup latency stalls the migrating task and the test
# fails with "Only performed N KVM_RUNs, task stalled too much?". Upstream's
# own advice is to bound the wakeup latency through /dev/cpu_dma_latency
# (what its "-l <latency>" option does) rather than skip the sanity check.
# The kselftest runner cannot pass per-test options, so fixup_kvm() holds the
# PM QoS request open for the whole group and clean_kvm() releases it.
#
# This extracts and executes the REAL fixup_kvm/clean_kvm function bodies,
# pointing /dev/cpu_dma_latency at a regular file and stubbing only the
# modprobe/lsmod environment probe.
describe 'kselftests kvm group cpu_dma_latency' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  def run_kvm_fixup(dir, latency_dev, probe)
    script = <<~BASH
      set -e
      lsmod() { echo kvm_intel; }
      modprobe() { :; }
      #{extract_function('fixup_kvm').gsub('/dev/cpu_dma_latency', latency_dev)}
      #{extract_function('clean_kvm')}
      cd #{dir}
      group=kvm
      mkdir -p $group
      fixup_kvm
      #{probe}
      clean_kvm
    BASH
    Bash.run(script)
  end

  it 'requests zero wakeup latency while the kvm group runs' do
    Dir.mktmpdir do |dir|
      latency_dev = "#{dir}/cpu_dma_latency"
      File.write(latency_dev, '')

      run_kvm_fixup(dir, latency_dev, '')

      expect(File.binread(latency_dev)).to eq([0].pack('l'))
    end
  end

  it 'keeps the request open until clean_kvm releases it' do
    Dir.mktmpdir do |dir|
      latency_dev = "#{dir}/cpu_dma_latency"
      File.write(latency_dev, '')

      output = run_kvm_fixup(dir, latency_dev,
                             'ls /proc/$$/fd | wc -l; ls -l /proc/$$/fd | grep -c cpu_dma_latency || true')

      # the descriptor is open when fixup_kvm returns (grep count 1), and the
      # trailing clean_kvm call must not fail.
      expect(output.lines.last.strip).to eq('1')
    end
  end

  it 'does not fail on a host without /dev/cpu_dma_latency' do
    Dir.mktmpdir do |dir|
      expect { run_kvm_fixup(dir, "#{dir}/missing", '') }.not_to raise_error
    end
  end
end
