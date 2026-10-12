require 'spec_helper'
require "#{LKP_SRC}/lib/bash"

# tools/testing/selftests/kvm/Makefile is the only kselftests
# group whose header search path depends on the literal $(ARCH) make
# variable (LINUX_TOOL_ARCH_INCLUDE resolves tools/arch/<ARCH>/include,
# which is where asm/msr-index.h and friends live). $(MAKE) only
# auto-forwards a variable to the recursive -C kvm sub-build when it was
# set on our own command line, so lib/tests/kselftests.sh's
# make_run_tests() must pass ARCH explicitly for the kvm group -- without
# it, $(ARCH) resolves empty and the include path becomes the
# non-existent tools/arch//include, hiding real headers that are present.
#
# This extracts and executes the REAL make_run_tests function body (not a
# hand-copied duplicate), stubbing only kselftests_make itself so no real
# `make` ever runs, and asserts on the exact argv it was invoked with.
describe 'kselftests kvm group ARCH handling' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  def run_make_run_tests(group, arch)
    script = <<~BASH
      set -e
      kselftests_make() { echo "CALL: $*"; }
      #{extract_function('make_run_tests')}
      group=#{group}
      arch=#{arch}
      make_run_tests
    BASH
    Bash.run(script)
  end

  it 'passes ARCH explicitly when building the kvm group' do
    output = run_make_run_tests('kvm', 'x86_64')

    expect(output).to match(/^CALL: ARCH=x86_64 TARGETS=kvm run_tests$/)
  end

  it 'derives ARCH from the job arch, not a hardcoded value' do
    output = run_make_run_tests('kvm', 'arm64')

    expect(output).to match(/^CALL: ARCH=arm64 TARGETS=kvm run_tests$/)
  end

  it 'does not add ARCH for other groups' do
    output = run_make_run_tests('bpf', 'x86_64')

    expect(output).to match(/^CALL: TARGETS=bpf run_tests$/)
    expect(output).not_to include('ARCH=')
  end
end
