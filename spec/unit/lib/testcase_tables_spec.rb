require 'spec_helper'
require "#{LKP_SRC}/lib/lkp_pattern"

# Regression test for the class of bug where MResultRootTableSet#testcase_to_table
# (lib/nresult_root.rb) raises "Unknow testcase" because a job's testcase: value
# was never added to any of etc/{linux-perf,linux,other}-test-cases.
describe 'every job testcase is registered in one of the 3 testcase tables' do
  def all_job_testcases
    Dir["#{LKP_SRC}/jobs/**/*.yaml"].filter_map do |file|
      line = File.readlines(file).find { |l| l =~ /^testcase:\s*(\S+)/ }
      Regexp.last_match(1) if line
    end.uniq
  end

  it 'is present in linux-perf-test-cases, linux-test-cases, or other-test-cases' do
    missing = all_job_testcases.reject do |testcase|
      # testcase_to_table strips this prefix before its own table lookup
      tc = testcase.sub(/^kvm:/, '')
      LKP::LinuxPerfTestCases.instance.contain?(tc) ||
        LKP::LinuxTestCases.instance.contain?(tc) ||
        LKP::OtherTestCases.instance.contain?(tc)
    end

    expect(missing).to be_empty,
                       "testcase(s) missing from etc/{linux-perf,linux,other}-test-cases: #{missing.join(', ')}"
  end
end
