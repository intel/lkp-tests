require 'spec_helper'
require "#{LKP_SRC}/lib/sparse_table_3d"

describe SparseTable3D do
  subject(:sparse_table_3d) { described_class.new }

  it 'stores and retrieves a value by x/y/z' do
    sparse_table_3d['h1', 't1', 'k1'] = %w(r1)

    expect(sparse_table_3d['h1', 't1', 'k1']).to eq %w(r1)
  end

  it 'returns nil for a coordinate with no value' do
    expect(sparse_table_3d['h1', 't1', 'k1']).to be_nil
  end

  describe '#x_labels/#y_labels/#z_labels' do
    before do
      sparse_table_3d['h1', 't1', 'k1'] = %w(r1)
      sparse_table_3d['h1', 't2', 'k1'] = %w(r2)
      sparse_table_3d['h2', 't1', 'k2'] = %w(r3)
    end

    it 'collects unique labels per axis' do
      expect(sparse_table_3d.x_labels).to contain_exactly('h1', 'h2')
      expect(sparse_table_3d.y_labels).to contain_exactly('t1', 't2')
      expect(sparse_table_3d.z_labels).to contain_exactly('k1', 'k2')
    end
  end

  describe '#to_table' do
    it 'renders an empty table with no data' do
      expect(sparse_table_3d.to_table { |cell| cell }.to_s).to eq "+--+\n|  |\n+--+\n|  |\n+--+\n+--+\n"
    end

    it 'renders a table with a header row per x/z combination and a row per y' do
      sparse_table_3d['h1', 't1', 'k1'] = %w(r1)
      sparse_table_3d['h1', 't2', 'k1'] = %w(r2)
      sparse_table_3d['h2', 't1', 'k2'] = %w(r3)

      table = sparse_table_3d.to_table { |jobs| jobs.join(',') }.to_s

      expect(table).to eq <<~TABLE
        +----+----+----+
        |    | h1 | h2 |
        +----+----+----+
        |    | k1 | k2 |
        +----+----+----+
        | t1 | r1 | r3 |
        | t2 | r2 |    |
        +----+----+----+
      TABLE
    end
  end
end
