#!/usr/bin/env ruby

require 'json'
require 'text-table'
require 'yaml'

# A 2D array implementation that behaves like a sparse matrix or a spreadsheet.
# It allows indexing by arbitrary row (i) and column (j) keys, not just integers.
#
#   +-------+-------+-------+
#   |       |   j   |   j   |  <- col index
#   +-------+-------+-------+
#   |   i   | val   | val   |
#   +-------+-------+-------+
#   |   i   | val   | val   |
#   +-------+-------+-------+
#       ^
#       |
#   row index
#
# @example
#   a = SparseTable.new
#   a['row1', 'col1'] = 10
#   a['row1', 'col2'] = 20
#   a.to_table
class SparseTable
  # Key used to store coordinates in the internal hash
  Key = Struct.new(:i, :j) do
    alias_method :row_index, :i
    alias_method :col_index, :j
  end

  # @param datas [Hash] Initial data hash keyed by SparseTable::Key(i, j)
  # @param default [Block] Block to return default value when accessing unset keys
  def initialize(datas = nil, &default)
    @datas = datas || {}
    @default = block_given? ? default : -> {}
  end

  # Get value at row i, column j
  def [](i, j)
    @datas[self.class.index(i, j)] || @default.call
  end

  # Set value at row i, column j
  def []=(i, j, data)
    @datas[self.class.index(i, j)] = data
  end

  # Transpose the 2D array (swap rows and columns)
  def transpose
    datas = @datas.transform_keys { |k| self.class.index(k.j, k.i) }

    self.class.new(datas, &@default)
  end

  # Convert the 2D array to a Text::Table object for printing
  # @param options [Hash]
  #   :x_widths [Integer] Split table into multiple tables if columns exceed this width
  #   :no_sort_col_index [Boolean] Disable automatic sorting of column indices
  #   :no_sort_row_index [Boolean] Disable automatic sorting of row indices
  #   :hide_row_index [Boolean] Do not include row indices in the output element
  def to_table(options = {}, &block)
    table = Text::Table.new

    col_indices = self.col_indices
    col_indices = col_indices.sort unless options[:no_sort_col_index]

    if options[:x_widths] && options[:x_widths] < col_indices.size
      col_indices.each_slice(options[:x_widths]).each do |x_slice|
        append_table(table, x_slice, options, &block)
      end
    else
      fill_table(table, col_indices, options, &block)
    end

    table
  end

  %i(to_yaml empty? values to_a).each do |name|
    define_method(name) do
      @datas.send(name)
    end
  end

  def to_json(*_args)
    # k is Key struct (i, j).
    # k.to_h.values -> [i, j]. reverse -> [j, i] (col, row)
    @datas.transform_keys { |k| [k.j, k.i] }.to_json
  end

  # define methods
  # - row_indices, col_indices
  # - row_values(i), col_values(j)
  # - row(i), col(j)
  # - rows, cols
  %i(row col).each do |dim|
    # Get all unique indices for the dimension (row or col)
    define_method("#{dim}_indices") do
      @datas.keys.map(&:"#{dim}_index").uniq
    end

    # Get a new SparseTable containing only the specified index of the dimension
    define_method(dim) do |dim_index|
      datas = @datas.select { |k, _v| dim_index == k.send("#{dim}_index") }.to_h
      self.class.new(datas, &@default)
    end

    # Get all values for the specified index of the dimension
    define_method("#{dim}_values") do |dim_index|
      send(dim, dim_index).values
    end

    # Iterate or map over the dimension, yielding index and content
    define_method("#{dim}s") do |&block|
      datas = send("#{dim}_indices").map do |dim_index|
        content = send(dim, dim_index)

        block.call(dim_index, content) ? content.to_a : nil
      end

      self.class.new(datas.compact.flatten(1).to_h, &@default)
    end

    # Iterate over indices of the dimension
    define_method("each_#{dim}") do |&block|
      send("#{dim}_indices").each(&block)
    end
  end

  # Remove all entries for a specific row index
  def delete_row!(row_index)
    @datas.delete_if { |k, _v| k.i == row_index }
  end

  # Create a copy of the SparseTable object with optionally transformed values
  # @yield [i, j, value] Optional block to transform values during copy
  #   @yieldparam i [Object] Row index
  #   @yieldparam j [Object] Column index
  #   @yieldparam value [Object] Cell value
  #   @yieldreturn [Object] New value for the cell
  def transform
    new_datas = if block_given?
                  @datas.each_with_object({}) do |(k, v), hash|
                    hash[k] = yield(k.i, k.j, v)
                  end
                else
                  @datas.dup
                end

    self.class.new(new_datas, &@default)
  end

  def each
    @datas.each do |k, v|
      yield(k.i, k.j, v)
    end
  end

  # Add a summary row that aggregates values for each column.
  # Defaults to summing integer values.
  # @param row_index [Object] The key for the new summary row (default: 'Total')
  # @yield [col_index, values] Optional block to calculate custom summary
  #   @yieldparam col_index [Object] Column index
  #   @yieldparam values [Array] Array of values in that column (excluding the summary row itself)
  def add_summary_row(row_index = 'Total')
    col_indices.each do |col_index|
      values = @datas.select { |k, _v| k.j == col_index && k.i != row_index }.values
      self[row_index, col_index] = if block_given?
                                     yield col_index, values
                                   else
                                     values.sum(&:to_i)
                                   end
    end
  end

  private

  def fill_table(table, col_indices, options)
    table.rows << ([''] + col_indices)

    row_indices = self.row_indices
    row_indices = row_indices.sort unless options[:no_sort_row_index]

    row_indices.each do |row_index|
      table.rows << ([row_index] + col_indices.map do |col_index|
        if block_given? && self[row_index, col_index]
          yield self[row_index, col_index]
        else
          self[row_index, col_index]
        end
      end)
    end

    table.rows.each { |row| row.delete_at(0) } if options[:hide_row_index]
  end

  def append_table(table, x_slice, options, &)
    slice = cols { |col_index, _col| x_slice.include? col_index }

    slice_rows = slice.to_table(&).rows

    table.rows += if slice.col_indices.size == options[:x_widths]
                    slice_rows
                  else
                    slice_rows.map { |row| row + [{ value: '', colspan: options[:x_widths] - slice.col_indices.size }] }
                  end

    table.rows << :separator
  end

  class << self
    def index(i, j)
      Key.new(i, j)
    end
  end
end
