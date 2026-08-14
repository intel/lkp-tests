require 'spec_helper'
require "#{LKP_SRC}/lib/stats"

describe LKP::PerfMetrics do
  let(:perf_metrics) { described_class.instance }

  describe '#contain?' do
    it 'matches a name exactly listed in etc/perf-metrics-prefixes' do
      expect(perf_metrics.contain?('boot-meminfo.DirectMap1G')).to be true
    end

    it 'matches a name that starts with a listed prefix' do
      expect(perf_metrics.contain?('boot-meminfo.DirectMap1GExtra')).to be true
    end

    it 'does not treat the prefix separator as a regex wildcard' do
      expect(perf_metrics.contain?('boot-meminfoXDirectMap1G')).to be false
    end

    it 'matches a name via a dynamically discovered test-name prefix' do
      expect(perf_metrics.contain?('hackbench.something')).to be true
    end

    it 'excludes a functional test name from the dynamic prefixes' do
      expect(perf_metrics.contain?('boot.something')).to be false
    end

    it 'matches a name via LKP::PerfMetricsPatterns, independent of any prefix' do
      expect(perf_metrics.contain?('time.foo')).to be true
    end

    it 'returns false for an unrelated name' do
      expect(perf_metrics.contain?('unrelated.stat')).to be false
    end
  end
end
