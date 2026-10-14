require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# mmu_stress_test (tools/testing/selftests/kvm) sizes itself from the host:
# 3/4 of the online CPUs as vCPUs plus a fixed 128G of guest memory. On a host
# with a couple of hundred CPUs it cannot finish within the kvm group's
# upstream "timeout=120" (tools/testing/selftests/kvm/settings), so
# fixup_kvm() in lib/tests/kselftests.sh must raise the group timeout.
#
# This extracts and executes the REAL fixup_kvm function body, stubbing only
# the modprobe/lsmod environment probe, and asserts on the settings file it
# leaves behind.
describe 'kselftests kvm group timeout' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  def run_fixup_kvm(dir)
    script = <<~BASH
      set -e
      lsmod() { echo kvm_intel; }
      modprobe() { :; }
      #{extract_function('fixup_kvm')}
      cd #{dir}
      group=kvm
      mkdir -p $group
      echo timeout=120 >$group/settings
      fixup_kvm
      cat $group/settings
    BASH
    Bash.run(script)
  end

  it 'replaces the upstream 120s timeout with a larger one' do
    Dir.mktmpdir do |dir|
      output = run_fixup_kvm(dir)

      timeout = output[/^timeout=(\d+)$/, 1]
      expect(timeout).not_to be_nil
      expect(timeout.to_i).to be > 120
    end
  end
end
