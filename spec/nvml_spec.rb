require 'spec_helper'
require "#{LKP_SRC}/lib/bash"

describe 'nvml' do
  describe 'check_param' do
    before(:all) do
      @benchmark_root = File.join(LKP_SRC, 'spec', 'benchmark_root')
    end

    it 'get correct testcases from group parameter' do
      [
        { group: 'ex', testcases: 'ex_libpmem ex_libpmem2 ex_libpmemobj ex_linkedlist ex_pmreorder' },
        { group: 'ex_libpmem', testcases: 'ex_libpmem' },
        { group: 'magic', testcases: 'magic' },
        { group: 'scope', testcases: 'scope' },
        { group: 'traces', testcases: 'traces_custom_function traces_pmem traces' }
      ].each do |entry|
        expect(Bash.run("source #{LKP_SRC}/lib/tests/nvml.sh; BENCHMARK_ROOT=#{@benchmark_root} group=#{entry[:group]} suite=nvml check_group_param 1>/dev/null; echo $testcases")).to eq(entry[:testcases])
      end
    end

    it 'cannot get testcases from group parameter' do
      [
        { group: 'wronggroup', output: 'Parameter group wronggroup is invalid' },
        { group: 'wrong_group', output: 'single test wrong_group is not found' }
      ].each do |entry|
        expect(Bash.run("source #{LKP_SRC}/lib/tests/nvml.sh; BENCHMARK_ROOT=#{@benchmark_root} group=#{entry[:group]} suite=nvml check_group_param 2>&1 1>/dev/null", returns: [99])).to match(/#{entry[:output]}/)
      end
    end
  end
end
