require 'spec_helper'
require "#{LKP_SRC}/lib/sparse_table"

describe SparseTable do
  let(:sparse_table) { described_class.new }

  describe '#initialize' do
    it 'initializes empty' do
      expect(sparse_table.empty?).to be true
    end

    it 'accepts a default block' do
      a = described_class.new { 0 }
      expect(a['foo', 'bar']).to eq(0)
    end
  end

  describe '#[] and #[]=' do
    it 'sets and gets values' do
      sparse_table['row1', 'col1'] = 'val1'
      expect(sparse_table['row1', 'col1']).to eq('val1')
    end

    it 'returns nil for unset values by default' do
      expect(sparse_table['row1', 'col1']).to be_nil
    end
  end

  describe '#transpose' do
    it 'swaps rows and columns' do
      sparse_table['r1', 'c1'] = 1
      sparse_table['r1', 'c2'] = 2
      t = sparse_table.transpose
      expect(t['c1', 'r1']).to eq(1)
      expect(t['c2', 'r1']).to eq(2)
      expect(t.row_indices).to contain_exactly('c1', 'c2')
    end
  end

  describe '#row_indices and #col_indices' do
    it 'returns unique indices' do
      sparse_table['r1', 'c1'] = 1
      sparse_table['r1', 'c2'] = 2
      sparse_table['r2', 'c1'] = 3
      expect(sparse_table.row_indices).to contain_exactly('r1', 'r2')
      expect(sparse_table.col_indices).to contain_exactly('c1', 'c2')
    end
  end

  describe '#row and #col' do
    before do
      sparse_table['r1', 'c1'] = 1
      sparse_table['r1', 'c2'] = 2
      sparse_table['r2', 'c1'] = 3
    end

    it 'returns a new SparseTable with selected row' do
      row = sparse_table.row('r1')
      expect(row['r1', 'c1']).to eq(1)
      expect(row['r1', 'c2']).to eq(2)
      expect(row.row_indices).to contain_exactly('r1')
    end

    it 'returns a new SparseTable with selected col' do
      col = sparse_table.col('c1')
      expect(col['r1', 'c1']).to eq(1)
      expect(col['r2', 'c1']).to eq(3)
      expect(col.col_indices).to contain_exactly('c1')
    end
  end

  describe '#delete_row!' do
    it 'deletes the specified row' do
      sparse_table['r1', 'c1'] = 1
      sparse_table['r2', 'c1'] = 2
      sparse_table.delete_row!('r1')
      expect(sparse_table.row_indices).to contain_exactly('r2')
      expect(sparse_table['r1', 'c1']).to be_nil
    end
  end

  describe '#add_summary_row' do
    before do
      sparse_table['r1', 'c1'] = 10
      sparse_table['r2', 'c1'] = 20
      sparse_table['r1', 'c2'] = 5
      sparse_table['r2', 'c2'] = 5
    end

    context 'without a block' do
      it 'sums integer values by default' do
        sparse_table.add_summary_row
        expect(sparse_table['Total', 'c1']).to eq(30)
        expect(sparse_table['Total', 'c2']).to eq(10)
      end

      it 'uses specified row index' do
        sparse_table.add_summary_row('Sum')
        expect(sparse_table['Sum', 'c1']).to eq(30)
      end

      it 'handles existing non-integer values with to_i' do
        sparse_table['r3', 'c1'] = '10'
        sparse_table.add_summary_row
        expect(sparse_table['Total', 'c1']).to eq(40) # 10+20+10
      end
    end

    context 'with a block' do
      it 'uses the block for calculation' do
        sparse_table.add_summary_row do |_col, values|
          values.sum(&:to_i) * 2
        end
        expect(sparse_table['Total', 'c1']).to eq(60) # (10+20)*2
        expect(sparse_table['Total', 'c2']).to eq(20) # (5+5)*2
      end

      it 'provides access to column index in block' do
        sparse_table.add_summary_row do |col, values|
          col == 'c1' ? values.sum : 0
        end
        expect(sparse_table['Total', 'c1']).to eq(30)
        expect(sparse_table['Total', 'c2']).to eq(0)
      end
    end

    it 'does not include the summary row itself in subsequent calculations if run twice' do
      sparse_table.add_summary_row
      expect(sparse_table['Total', 'c1']).to eq(30)

      # Modify a value
      sparse_table['r1', 'c1'] = 15

      # Run again, should recalculate correctly without including previous total
      sparse_table.add_summary_row
      expect(sparse_table['Total', 'c1']).to eq(35) # 15 + 20
    end
  end

  describe '#transform' do
    before do
      sparse_table['r1', 'c1'] = 1
      sparse_table['r1', 'c2'] = 2
    end

    it 'creates a shallow copy without a block' do
      copy = sparse_table.transform
      expect(copy['r1', 'c1']).to eq(1)
      expect(copy['r1', 'c2']).to eq(2)

      # Modify copy, original should not change
      copy['r1', 'c1'] = 99
      expect(sparse_table['r1', 'c1']).to eq(1)
    end

    it 'transforms values when a block is provided' do
      copy = sparse_table.transform do |_i, _j, value|
        value * 10
      end
      expect(copy['r1', 'c1']).to eq(10)
      expect(copy['r1', 'c2']).to eq(20)
    end

    it 'allows conditional transformation based on indices' do
      copy = sparse_table.transform do |_i, j, value|
        j == 'c1' ? value + 100 : value
      end
      expect(copy['r1', 'c1']).to eq(101)
      expect(copy['r1', 'c2']).to eq(2)
    end
  end

  describe '#to_table' do
    it 'returns a Text::Table object' do
      sparse_table['r1', 'c1'] = 'val'
      expect(sparse_table.to_table).to be_a(Text::Table)
    end
  end

  describe '#to_json' do
    it 'returns valid JSON with swapped keys [col, row]' do
      sparse_table['r1', 'c1'] = 10
      json = sparse_table.to_json
      parsed = JSON.parse(json)

      # The key in JSON will be the string representation of [col, row] array
      # Because JSON keys are always strings

      # Since JSON.dump of a ruby Hash with array keys converts keys to strings differently
      # We need to check carefully.
      # Actually, Ruby's to_json on a Hash calls to_s on keys.
      # [1, 2].to_s => "[1, 2]"

      expect(parsed).to have_key('["c1", "r1"]')
      expect(parsed['["c1", "r1"]']).to eq(10)
    end
  end
end
