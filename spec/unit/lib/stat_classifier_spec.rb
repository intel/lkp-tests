require 'spec_helper'
require "#{LKP_SRC}/lib/stats"

describe StatClassifier do
  describe '.function_stat?' do
    it 'treats a matched failure pattern as a function stat' do
      expect(described_class.function_stat?('dmesg.INFO:task_blocked_for_more_than#seconds')).to be true
      expect(described_class.function_stat?('xfstests.btrfs.192.fail')).to be true
    end

    it 'does not treat an unmatched stat as a function stat' do
      expect(described_class.function_stat?('perf-profile.calltrace.cycles-pp.error_entry')).to be false
    end

    it 'excludes .time./.timestamp:/.bootstage: stats before checking patterns' do
      expect(described_class.function_stat?('foo.time.bar')).to be false
      expect(described_class.function_stat?('foo.timestamp:bar')).to be false
      expect(described_class.function_stat?('foo.bootstage:bar')).to be false
    end
  end

  describe '.failure_stat?' do
    it 'matches etc/failure patterns' do
      expect(described_class.failure_stat?('dmesg.INFO:task_blocked_for_more_than#seconds')).to be true
      expect(described_class.failure_stat?('perf-profile.calltrace.cycles-pp.error_entry')).to be false
    end
  end

  describe '.pass_stat?' do
    it 'matches an etc/pass-suffixed stat' do
      expect(described_class.pass_stat?('xfstests.generic.001.pass')).to be true
      expect(described_class.pass_stat?('xfstests.generic.001.fail')).to be false
    end
  end

  describe '.memory_stat?' do
    it 'matches an etc/memory-stat-prefixes prefix' do
      expect(described_class.memory_stat?('meminfo.MemFree')).to be true
    end

    it 'does not match a monitor outside that prefix list' do
      expect(described_class.memory_stat?('vmstat.something')).to be false
    end
  end

  describe '.bisectable_stat?' do
    it 'allows a stat matched by the allowlist even if also denylisted' do
      expect(described_class.bisectable_stat?('stderr.umount:/tmp/vm-scalability-tmp:target_is_busy')).to be true
    end

    it 'denies a stat matched only by the denylist' do
      expect(described_class.bisectable_stat?('ebizzy.throughput.per_thread.stddev_percent')).to be false
    end

    it 'allows a stat matched by neither list' do
      expect(described_class.bisectable_stat?('some.random.stat')).to be true
    end
  end

  describe '.kpi_stat?' do
    it 'excludes stats on the hardcoded KPI_STAT_DENYLIST' do
      expect(described_class.kpi_stat?('vm-scalability.stddev', nil)).to be false
      expect(described_class.kpi_stat?('unixbench.incomplete_result', nil)).to be false
    end

    it 'accepts a stat whose base is a known test' do
      expect(described_class.kpi_stat?('vm-scalability.throughput', nil)).to be true
    end

    it "excludes a known test's time. stats" do
      expect(described_class.kpi_stat?('vm-scalability.time.elapsed', nil)).to be false
    end

    it "rejects a stat whose base isn't a known test" do
      expect(described_class.kpi_stat?('nonexistent-test.throughput', nil)).to be false
    end
  end
end
