require 'spec_helper'
require "#{LKP_SRC}/lib/stats"

expects = {
  'dmesg.INFO:task_blocked_for_more_than#seconds' => true,
  'last_state.load_disk_fail' => true,
  'xfstests.btrfs.192.fail' => true,
  'perf-profile.calltrace.cycles-pp.error_entry' => false
}

describe 'failure stat' do
  expects.each do |k, v|
    it k do
      expect(StatClassifier.failure_stat?(k)).to eq v
    end
  end
end
