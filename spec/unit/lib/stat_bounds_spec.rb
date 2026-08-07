require 'spec_helper'
require "#{LKP_SRC}/lib/stat_bounds"

describe StatBounds do
  after do
    described_class.singleton_class.cache_store(:range_for).clear
  end

  describe '.valid?' do
    it 'accepts a value within the monitor field range' do
      expect(described_class.valid?('turbostat.Package.Watt', 5000)).to be true
    end

    it 'rejects a value outside the monitor field range' do
      expect(described_class.valid?('turbostat.Package.Watt', 50_000)).to be false
    end

    it 'accepts any value when the monitor has no valid-range file' do
      expect(described_class.valid?('nonexistentmonitor.foo', 5)).to be true
    end
  end

  describe '.range_for' do
    it 'returns nil for a monitor with no valid-range file' do
      expect(described_class.range_for('nonexistentmonitor')).to be_nil
    end

    it 'caches the lookup so a second call skips re-parsing the file' do
      allow(JSON).to receive(:parse_cached).and_call_original

      described_class.range_for('turbostat')
      described_class.range_for('turbostat')

      expect(JSON).to have_received(:parse_cached).once
    end
  end
end
