require 'spec_helper'
require 'set'
require "#{LKP_SRC}/lib/nm"

describe 'add_sign' do
  it 'prefixes a positive number with +' do
    expect(add_sign(5)).to eq('+5')
  end

  it 'does not prefix a negative number' do
    expect(add_sign(-5)).to eq('-5')
  end

  it 'does not prefix zero' do
    expect(add_sign(0)).to eq('0')
  end

  it 'returns an empty string for nil' do
    expect(add_sign(nil)).to eq('')
  end
end

describe SymbolSize do
  let(:symbol_size) { described_class.new(nil, nil) }

  describe '.readable_symbol_name' do
    it 'maps known nm.* symbols to their readable name' do
      expect(described_class.readable_symbol_name('nm.total')).to eq('TOTAL')
      expect(described_class.readable_symbol_name('nm.bss')).to eq('BSS')
    end

    it 'formats a function symbol as a call' do
      expect(described_class.readable_symbol_name('nm.t.do_fork')).to eq('do_fork()')
      expect(described_class.readable_symbol_name('nm.T.do_fork')).to eq('do_fork()')
    end

    it 'passes through an unmatched function-style symbol name' do
      expect(described_class.readable_symbol_name('nm.d.some_data')).to eq('some_data')
    end

    it 'strips vmlinux./built-in.(a|o) suffixes for other symbols' do
      expect(described_class.readable_symbol_name('vmlinux.text')).to eq('text')
      expect(described_class.readable_symbol_name('fs/built-in.o')).to eq('fs/')
    end
  end

  describe '#reduce_overlap_symbols' do
    it 'drops a nested built-in.o already covered by its parent built-in.o' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['arch/x86/built-in.o', 'arch/x86/vdso/built-in.o']))
      symbol_size.reduce_overlap_symbols
      expect(symbol_size.instance_variable_get(:@symbols)).to contain_exactly('arch/x86/vdso/built-in.o')
    end

    it 'drops a two-level nested built-in.o whose parent built-in.o is absent' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['arch/x86/built-in.o']))
      symbol_size.reduce_overlap_symbols
      expect(symbol_size.instance_variable_get(:@symbols)).to be_empty
    end

    it 'keeps a top-level built-in.o with no parent directory' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['built-in.o']))
      symbol_size.reduce_overlap_symbols
      expect(symbol_size.instance_variable_get(:@symbols)).to contain_exactly('built-in.o')
    end

    it 'drops a vmlinux.* symbol already covered by a mapped nm.* symbol' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['vmlinux.total']))
      symbol_size.reduce_overlap_symbols
      expect(symbol_size.instance_variable_get(:@symbols)).to be_empty
    end

    it 'drops all nm.* symbols when invalid per-index nm data is found' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['nm.t.foo0', 'nm.total']))
      symbol_size.reduce_overlap_symbols
      expect(symbol_size.instance_variable_get(:@symbols)).to be_empty
    end
  end

  describe '#any_significant_change?' do
    it 'returns false when no commit range has been computed' do
      expect(symbol_size.any_significant_change?).to be false
    end

    it 'returns false when nm.total was not among the changed symbols' do
      symbol_size.instance_variable_set(:@all_commits_range, 'a..b')
      symbol_size.instance_variable_set(:@symbols, Set.new(['nm.text']))
      expect(symbol_size.any_significant_change?).to be false
    end

    it 'returns true when a symbol changed by at least MINIMAL_CHANGE' do
      symbol_size.instance_variable_set(:@all_commits_range, 'a..b')
      symbol_size.instance_variable_set(:@symbols, Set.new(['nm.total']))
      symbol_size.instance_variable_set(:@diff, { 'a..b' => { 'nm.total' => 100 } })
      expect(symbol_size.any_significant_change?).to be true
    end

    it 'returns false when the change is below MINIMAL_CHANGE' do
      symbol_size.instance_variable_set(:@all_commits_range, 'a..b')
      symbol_size.instance_variable_set(:@symbols, Set.new(['nm.total']))
      symbol_size.instance_variable_set(:@diff, { 'a..b' => { 'nm.total' => 10 } })
      expect(symbol_size.any_significant_change?).to be false
    end
  end

  describe '#count_significant_changes' do
    it 'counts symbols and commits with a significant change' do
      symbol_size.instance_variable_set(:@symbols, Set.new(%w[nm.total nm.text]))
      symbol_size.instance_variable_set(:@diff, {
                                          'c1' => { 'nm.total' => 100, 'nm.text' => 10 },
                                          'c2' => { 'nm.total' => 0, 'nm.text' => 0 }
                                        })
      expect(symbol_size.count_significant_changes).to eq(1)
      expect(symbol_size.instance_variable_get(:@nr_significant_commits)).to eq(1)
    end
  end

  describe '#sort_symbols' do
    it 'orders symbols by SYMBOL_NAME_ORDER, then by delta in the full range' do
      symbol_size.instance_variable_set(:@all_commits_range, 'a..b')
      symbol_size.instance_variable_set(:@symbols, Set.new(%w[nm.bss nm.total nm.text]))
      symbol_size.instance_variable_set(:@diff, { 'a..b' => { 'nm.bss' => 1, 'nm.total' => 2, 'nm.text' => 3 } })
      expect(symbol_size.sort_symbols).to eq(%w[nm.total nm.text nm.bss])
    end
  end

  describe '#split_sparse_symbols' do
    it 'moves a symbol changed in fewer commits than the threshold into sparse_changes' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['nm.total']))
      symbol_size.instance_variable_set(:@diff, { 'c1' => { 'nm.total' => 5 } })
      symbol_size.split_sparse_symbols(2)
      expect(symbol_size.instance_variable_get(:@symbols)).to be_empty
      expect(symbol_size.instance_variable_get(:@sparse_changes)['nm.total']).to contain_exactly([5, 'c1'])
    end

    it 'keeps a symbol changed in more commits than the threshold' do
      symbol_size.instance_variable_set(:@symbols, Set.new(['nm.total']))
      symbol_size.instance_variable_set(:@diff, {
                                          'c1' => { 'nm.total' => 5 },
                                          'c2' => { 'nm.total' => 7 }
                                        })
      symbol_size.split_sparse_symbols(1)
      expect(symbol_size.instance_variable_get(:@symbols)).to contain_exactly('nm.total')
    end
  end

  describe '#sort_sparse_changes' do
    it 'orders sparse symbols by SYMBOL_NAME_ORDER, then by their largest delta' do
      symbol_size.instance_variable_set(:@sparse_changes, {
                                          'nm.bss' => [[1, 'c1']],
                                          'nm.total' => [[2, 'c1']]
                                        })
      symbol_size.sort_sparse_changes
      expect(symbol_size.instance_variable_get(:@sparse_changes).keys).to eq(%w[nm.total nm.bss])
    end

    it 'does nothing when no sparse changes were computed' do
      expect { symbol_size.sort_sparse_changes }.not_to raise_error
      expect(symbol_size.instance_variable_get(:@sparse_changes)).to be_nil
    end
  end

  describe '#show_changes' do
    it 'renders a dense table and returns nil when no commit exceeds the maximum change' do
      allow(symbol_size).to receive(:diff_kernel_size).and_return({ 'nm.total' => 100 })
      allow(symbol_size).to receive(:commit_name) { |commit| commit }

      expect(symbol_size.show_changes(%w[aaaaaaaaaaaa bbbbbbbbbbbb])).to be_nil
      expect(symbol_size.instance_variable_get(:@symbols)).to contain_exactly('nm.total')
    end

    it 'does nothing when there is no pair of commits to diff' do
      expect(symbol_size.show_changes(['aaaaaaaaaaaa'])).to be_nil
      expect(symbol_size.instance_variable_get(:@diff)).to be_empty
    end
  end
end
