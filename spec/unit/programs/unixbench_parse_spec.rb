require 'spec_helper'
require 'open3'

# Regression guard for programs/unixbench/parse's X-server-crash detection.
#
# stats_spec.rb's golden-fixture harness only compares stdout (Bash.run
# returns result.out, never result.err), so it cannot catch a regression in
# which "fail" fails to be set to true: in both the fail and non-fail paths
# duration/throughput stay nil, so stdout is identically "test.fail: 1" --
# only the stderr log_warn call differs (lib/log.rb's log_warn writes to
# $stderr). Exercise the real script as a subprocess and assert on stderr
# directly so a crash signature that doesn't set fail=true (and therefore
# emits a misleading "miss duration or throughput" warning instead of being
# cleanly classified as a known X-server crash) is caught.
describe 'programs/unixbench/parse' do
  let(:parse_script) { "#{LKP_SRC}/programs/unixbench/parse" }

  def run_parse(raw_output)
    Open3.capture3({ 'LKP_SRC' => LKP_SRC, 'RESULT_ROOT' => '/result/unixbench/test' }, parse_script,
                   stdin_data: raw_output)
  end

  it 'does not warn when the X server crashes with a fatal server error' do
    raw_output = <<~RAW
      1 x 2D graphics: polygons  1 2 3 4 5
      6(EE)
      Fatal server error:
      (EE) xf86OpenConsole: Switching VT failed
      (EE)
      xinit: connection to X server lost
    RAW

    stdout, stderr, = run_parse(raw_output)

    expect(stdout).to eq "test.fail: 1\n"
    expect(stderr).not_to include('miss duration or throughput')
  end

  it 'still warns when duration/throughput are missing for an unrecognized reason' do
    raw_output = "some unrelated unrecognized output\n"

    stdout, stderr, = run_parse(raw_output)

    expect(stdout).to eq "test.fail: 1\n"
    expect(stderr).to include('miss duration or throughput')
  end
end
