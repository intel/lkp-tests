require 'spec_helper'
require 'json'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# tc-testing/tc-tests/qdiscs/teql.json does not use the nsPlugin, so tdc runs
# its tests serially in the host's own network namespace. Test 7734 adds a
# dummy device named by $ETH ("eth0"), which collides with a real NIC on any
# host that has one ("RTNETLINK answers: File exists"). Tests in other files
# use $ETH inside a per-test namespace, where eth0 is a netdevsim device, so
# $ETH itself must stay as is; only teql.json switches to the per-test $DEV1.
#
# This extracts and executes the REAL fixup_tc_testing_teql_eth function body
# (not a hand-copied duplicate) against a teql.json shaped like the upstream one.
describe 'kselftests tc-testing teql device name' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }

  let(:teql_tests) do
    [
      { 'id' => '84a0', 'setup' => ['$IP link add dev $DUMMY type dummy'] },
      {
        'id' => '7734',
        'setup' => ['$IP link add dev $DUMMY type dummy',
                    '$IP link add dev $ETH type dummy',
                    '$TC qdisc add dev $ETH handle 1: root teql0'],
        'teardown' => ['$IP link del dev $ETH']
      }
    ]
  end

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  def fixup(tests)
    Dir.mktmpdir do |dir|
      json_dir = File.join(dir, 'tc-testing/tc-tests/qdiscs')
      FileUtils.mkdir_p(json_dir)
      File.write(File.join(json_dir, 'teql.json'), JSON.pretty_generate(tests))

      Bash.run("cd #{dir} && #{extract_function('fixup_tc_testing_teql_eth')}\nfixup_tc_testing_teql_eth")

      JSON.parse(File.read(File.join(json_dir, 'teql.json')))
    end
  end

  it 'stops using the host-visible $ETH name in setup and teardown' do
    test = fixup(teql_tests).find { |t| t['id'] == '7734' }

    expect(test['setup']).to eq(['$IP link add dev $DUMMY type dummy',
                                 '$IP link add dev $DEV1 type dummy',
                                 '$TC qdisc add dev $DEV1 handle 1: root teql0'])
    expect(test['teardown']).to eq(['$IP link del dev $DEV1'])
  end

  it 'leaves tests that do not use $ETH untouched' do
    expect(fixup(teql_tests).find { |t| t['id'] == '84a0' }).to eq(teql_tests.first)
  end

  it 'is wired into fixup_tc_testing' do
    expect(extract_function('fixup_tc_testing')).to match(/^\tfixup_tc_testing_teql_eth$/)
  end
end
