#!/usr/bin/env ruby

require 'text-table'

class SparseTable3D
  attr_reader :cells

  def initialize(cells = nil)
    @cells = cells || {}
  end

  def [](x, y, z)
    @cells[[x, y, z]]
  end

  def []=(x, y, z, data)
    @cells[[x, y, z]] = data
  end

  def to_table(&)
    table = Text::Table.new

    x_labels = self.x_labels.sort
    z_labels = self.z_labels.sort

    table.head = [''] + x_labels.map { |x_label| { value: x_label, colspan: z_labels.count { |z_label| xz_point?(x_label, z_label) } } }

    z_labels_by_x = x_labels.map { |x_label| z_labels.select { |z_label| xz_point?(x_label, z_label) } }
    table.rows << ([''] + z_labels_by_x.flatten.map { |z_label| { value: z_label, align: :center } })
    table.rows << :separator

    y_labels.sort.each do |y_label|
      row = [y_label]

      row += x_labels.flat_map.with_index do |x_label, index|
        z_labels_by_x[index].map { |z_label| yield self[x_label, y_label, z_label] if self[x_label, y_label, z_label] }
      end

      table.rows << row
    end

    table
  end

  def x_labels
    @cells.keys.map(&:first).uniq
  end

  def y_labels
    @cells.keys.map { |k| k[1] }.uniq
  end

  def z_labels
    @cells.keys.map(&:last).uniq
  end

  private

  def xz_point?(x_label, z_label)
    @cells.keys.any? { |x, _y, z| x == x_label && z == z_label }
  end
end
