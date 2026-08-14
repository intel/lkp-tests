require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/lkp_pattern"

describe LKP::PatternValues do
  around do |example|
    Dir.mktmpdir do |dir|
      @file = File.join(dir, 'weight.yaml')
      File.write(@file, <<~YAML)
        dmesg.*(BUG|PANIC): 50
        aim9\\..+\\.ops_per_sec: 1
      YAML

      example.run
    end
  end

  let(:pattern_values) { described_class.new(@file) }

  describe '#value' do
    it 'returns the value of the first key whose pattern matches content' do
      expect(pattern_values.value('dmesg.BUG: kernel oops')).to eq 50
    end

    it 'returns nil when no key pattern matches' do
      expect(pattern_values.value('unrelated.stat')).to be_nil
    end
  end

  describe '#key' do
    it 'returns the first key whose pattern fully matches content' do
      expect(pattern_values.key('aim9.add_double.ops_per_sec')).to eq 'aim9\\..+\\.ops_per_sec'
    end

    it 'returns nil when no key pattern matches' do
      expect(pattern_values.key('unrelated.stat')).to be_nil
    end

    it 'drops candidate keys matching exclude before searching' do
      expect(pattern_values.key('aim9.add_double.ops_per_sec', exclude: /^aim9/)).to be_nil
    end
  end

  describe '#[]' do
    it 'returns the value stored under an exact key' do
      expect(pattern_values['aim9\\..+\\.ops_per_sec']).to eq 1
    end

    it 'returns nil for an unknown key' do
      expect(pattern_values['unknown']).to be_nil
    end
  end

  describe '#keys' do
    it 'returns every pattern key in the file' do
      expect(pattern_values.keys).to contain_exactly('dmesg.*(BUG|PANIC)', 'aim9\\..+\\.ops_per_sec')
    end
  end
end

describe LKP::Pattern do
  around do |example|
    Dir.mktmpdir do |dir|
      @file = File.join(dir, 'patterns')
      File.write(@file, <<~PATTERNS)
        cpuidle\\.
        # a comment line, not a pattern
        time\\.user_time
      PATTERNS

      example.run
    end
  end

  describe 'anchor: :none (default)' do
    let(:pattern) { described_class.new(@file) }

    it 'matches content containing a pattern anywhere' do
      expect(pattern.contain?('xcpuidle.C1')).to be true
    end

    it 'ignores comment lines' do
      expect(pattern.contain?('# a comment line, not a pattern')).to be false
    end

    it 'returns false for unrelated content' do
      expect(pattern.contain?('unrelated.stat')).to be false
    end
  end

  describe 'anchor: :start' do
    let(:pattern) { described_class.new(@file, anchor: :start) }

    it 'matches a name that starts with one of the patterns' do
      expect(pattern.contain?('cpuidle.C1')).to be true
    end

    it 'matches a pattern with no trailing separator as a start match' do
      expect(pattern.contain?('time.user_time')).to be true
    end

    it 'returns false for a name that only contains a pattern as a substring' do
      expect(pattern.contain?('xcpuidle.C1')).to be false
    end

    it 'returns false for an unrelated name' do
      expect(pattern.contain?('unrelated.stat')).to be false
    end
  end

  describe 'anchor: :full' do
    let(:pattern) { described_class.new(@file, anchor: :full) }

    it 'matches content that fully equals a pattern' do
      expect(pattern.contain?('time.user_time')).to be true
    end

    it 'returns false when content only starts with a pattern' do
      expect(pattern.contain?('time.user_time_extra')).to be false
    end
  end
end

describe LKP::Prefixes do
  around do |example|
    Dir.mktmpdir do |dir|
      @file = File.join(dir, 'prefixes')
      File.write(@file, <<~PREFIXES)
        cpuidle.
        # a comment line, not a prefix
        time.user_time
      PREFIXES

      example.run
    end
  end

  let(:prefixes) { described_class.new(@file) }

  describe '#contain?' do
    it 'matches a name that starts with one of the literal prefixes' do
      expect(prefixes.contain?('cpuidle.C1')).to be true
    end

    it 'matches a prefix line with no trailing dot as an exact-start match' do
      expect(prefixes.contain?('time.user_time')).to be true
    end

    it 'returns false for a name that only contains a prefix as a substring' do
      expect(prefixes.contain?('xcpuidle.C1')).to be false
    end

    it 'ignores comment lines' do
      expect(prefixes.contain?('# a comment line, not a prefix')).to be false
    end

    it 'returns false for an unrelated name' do
      expect(prefixes.contain?('unrelated.stat')).to be false
    end
  end
end
