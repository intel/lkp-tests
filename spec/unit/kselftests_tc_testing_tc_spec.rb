require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# tdc runs the distro's tc by a fixed default path. That
# one can be too old for the qdiscs under test (iproute2 v6.15 does not know
# dualpi2 and reports 'Unknown qdisc "dualpi2"', which fails the test's
# setup/teardown). The kselftests package therefore builds a current tc, and
# fixup_tc_testing_tc points tdc at it through tdc's own local-override file.
#
# This extracts and executes the REAL fixup_tc_testing_tc function body (not a
# hand-copied duplicate) in a scratch directory laid out like the selftests tree.
describe 'kselftests tc-testing tc override' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  def run_fixup(tc_path)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'tc-testing'))
      File.write(File.join(dir, 'tc'), "#!/bin/sh\n")
      File.chmod(0o755, File.join(dir, 'tc'))

      Bash.run("cd #{dir} && #{extract_function('fixup_tc_testing_tc')}\nfixup_tc_testing_tc #{tc_path.sub('DIR', dir)}")

      config = File.join(dir, 'tc-testing/tdc_config_local.py')
      File.exist?(config) ? File.read(config).sub(dir, 'DIR') : nil
    end
  end

  it 'points tdc at the built tc when it is installed' do
    expect(run_fixup('DIR/tc')).to eq("EXTRA_NAMES = {'TC': 'DIR/tc'}\n")
  end

  it 'keeps the distro tc when the built tc is not installed' do
    expect(run_fixup('DIR/missing-tc')).to be_nil
  end

  it 'writes an override that tdc_config.py accepts' do
    config = run_fixup('DIR/tc')

    expect(Bash.run("python3 -c \"#{config.tr("\n", ';')}print(EXTRA_NAMES['TC'], end='')\"")).to eq('DIR/tc')
  end

  it 'is wired into fixup_tc_testing' do
    expect(extract_function('fixup_tc_testing')).to match(%r{^\tfixup_tc_testing_tc /usr/local/lib/iproute2/tc$})
  end
end
