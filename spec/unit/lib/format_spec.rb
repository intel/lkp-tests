require 'spec_helper'
require "#{LKP_SRC}/lib/format"

describe '#humanize_time' do
  [
    [0, '         0'],
    [59, '        59'],
    [60, '      1:00'],
    [3661, '   1:01:01'],
    [90_000, ' 1:01:00:00']
  ].each do |seconds, expected|
    it "formats #{seconds}s as #{expected.strip.inspect}" do
      expect(humanize_time(seconds)).to eq expected
    end
  end
end

describe LKP::Format do
  describe '.completion' do
    it 'shows just the count when completed equals total' do
      expect(described_class.completion(10, 10)).to eq '10'
    end

    it 'shows completed/total when not fully completed' do
      expect(described_class.completion(5, 10)).to eq '5/10'
    end

    it 'prepends a percentage when requested' do
      expect(described_class.completion(5, 10, percentage: true)).to eq '50% (5/10)'
    end
  end

  describe '.count_with_percentage' do
    it 'formats count, percentage of sum, and name' do
      expect(described_class.count_with_percentage(160, 483, 'kernel test robot')).to eq ' 160 33.1% kernel test robot'
    end
  end

  describe '.condensed_ranges' do
    it 'condenses consecutive numbers into ranges' do
      expect(described_class.condensed_ranges([1, 2, 3, 4, 5, 8, 9, 11])).to eq '1 - 5, 8 - 9, 11'
    end

    it 'returns an empty string for no numbers' do
      expect(described_class.condensed_ranges([])).to eq ''
    end

    it 'returns a single number unchanged' do
      expect(described_class.condensed_ranges([5])).to eq '5'
    end
  end
end
