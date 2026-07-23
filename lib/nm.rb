#!/usr/bin/env ruby

require 'text-table'

def add_sign(n)
  if n.nil?
    ''
  elsif n.positive?
    "+#{n}"
  else
    n.to_s
  end
end

class SymbolSize
  MINIMAL_CHANGE   = 64
  MAXIMUM_CHANGE   = 9999
  DEFAULT_KCONFIG  = 'i386-tinyconfig'.freeze
  DEFAULT_COMPILER = 'gcc-5'.freeze

  SYMBOL_NAME_MAP = {
    'nm.total' => 'TOTAL',
    'nm.text' => 'TEXT',
    'nm.data' => 'DATA',
    'nm.rodata' => 'RODATA',
    'nm.bss' => 'BSS',
    'nm.brk' => 'BRK'
  }.freeze

  SYMBOL_NAME_ORDER = {
    'nm.total' => 1_119_111,
    'nm.text' => 1_118_111,
    'nm.data' => 1_117_111,
    'nm.rodata' => 1_115_111,
    'nm.bss' => 1_114_111,
    'nm.brk' => 1_113_111
  }.freeze

  def initialize(kconfig, compiler)
    @kconfig  = kconfig || DEFAULT_KCONFIG
    @compiler = compiler || DEFAULT_COMPILER
  end

  def self.readable_symbol_name(symbol)
    if SYMBOL_NAME_MAP.include? symbol
      SYMBOL_NAME_MAP[symbol]
    elsif symbol =~ /^nm\.(.)\.(.*)$/
      if $1 == 't' || $1 == 'T'
        "#{$2}()"
      else
        $2
      end
    else
      symbol.sub(/^vmlinux\.|built-in\.(a|o)$/, '')
    end
  end

  def diff_commits(commits)
    @commits = commits
    @diff = {}

    prev_commit = commits.first
    @commits.each do |commit|
      next if prev_commit == commit

      diff = diff_kernel_size(@kconfig, @compiler, prev_commit, commit)
      prev_commit = commit
      next unless diff

      @diff[commit] = diff
    end

    return if @diff.empty?

    base_commit = commits.first
    last_commit = commits.last
    total_diff = diff_kernel_size(@kconfig, @compiler, base_commit, last_commit)
    if total_diff
      @all_commits_range = "#{base_commit[0..11]}..#{last_commit[0..11]} (ALL COMMITS)"
      @diff[@all_commits_range] = total_diff
    end

    @diff
  end

  def changed_symbols
    @symbols = Set.new
    @diff.each_value do |diff|
      diff.each_key do |symbol|
        next unless diff[symbol].abs >= MINIMAL_CHANGE

        @symbols << symbol
      end
    end
    @symbols
  end

  def reduce_overlap_symbols
    # $ diff -u 3b78fae793c027140cfe635ef216bf60aa6498f4/kernel_size.json \
    #           c93a59938c11f447ff2964ab3c317311778edf66/kernel_size.json | grep built-in
    # "arch/x86/built-in.o": 365120,
    # +  "arch/x86/vdso/built-in.o": 15112,
    #
    # The vdso change is false positive because the parent dir's
    # built-in.o does not change at all.
    @symbols.delete_if do |symbol|
      case symbol
      when /(.*)\/built-in.(a|o)$/
        dir = File.dirname $1
        if dir == '.'
          false
        else
          !@symbols.include?("#{dir}/built-in.a") && !@symbols.include?("#{dir}/built-in.o")
        end
      else
        false
      end
    end

    invalid_nm_data = false
    @symbols.delete_if do |symbol|
      case symbol
      when /(.*\/)built-in.(a|o)$/
        #   arch/x86/mm/built-in.o
        # - arch/x86/built-in.o
        #   kernel/built-in.o
        dir = $1
        @symbols.any? { |s| s != symbol && s.start_with?(dir) }
      when /^vmlinux\.(.*)/
        SYMBOL_NAME_MAP.include? "nm.#{$1}"
      when /^nm\..*[0-9]$/
        invalid_nm_data = true
        true
      when /^nm\..\.total$/
        true
      else
        false
      end
    end

    @symbols.delete_if { |symbol| symbol =~ /^nm\./ } if invalid_nm_data
  end

  def any_significant_change?
    return false unless @all_commits_range
    return false unless @symbols.include? 'nm.total'

    diff = @diff[@all_commits_range]
    @symbols.any? { |symbol| diff[symbol] && diff[symbol].abs >= MINIMAL_CHANGE }
  end

  def count_significant_changes
    @nr_significant_changes = 0
    @nr_significant_commits = 0
    @diff.each_value do |diff|
      nr = @symbols.count { |symbol| diff[symbol] && diff[symbol].abs >= MINIMAL_CHANGE }
      @nr_significant_commits += 1 if nr.positive?
      @nr_significant_changes += nr
    end
    @nr_significant_changes
  end

  def sort_symbols
    @symbols = @symbols.sort_by do |symbol|
      order = SYMBOL_NAME_ORDER[symbol] || 0
      delta = @diff[@all_commits_range][symbol] || 0
      - order - delta
    end
  end

  def split_sparse_symbols(thresh)
    @sparse_changes = {}
    @symbols.delete_if do |symbol|
      sparse_changes = []
      @diff.each do |commit, v|
        delta = v[symbol]
        next unless delta
        next unless delta != 0

        sparse_changes << [delta, commit]
      end
      if sparse_changes.empty? || sparse_changes.size > thresh
        false
      else
        if sparse_changes.size == 2 &&
           sparse_changes.first[0] == sparse_changes.last[0]
          if sparse_changes.last[1] == @all_commits_range
            sparse_changes.pop
          elsif sparse_changes.first[1] == @all_commits_range
            sparse_changes.unshift
          end
        end

        @sparse_changes[symbol] = sparse_changes.sort_by do |v|
          if v.last == @all_commits_range
            - v.first - 99_999
          else
            - v.first
          end
        end
        true
      end
    end
  end

  def show_dense_changes
    return if @symbols.empty?

    table = Text::Table.new vertical_boundary: '=',
                            horizontal_boundary: '',
                            boundary_intersection: '',
                            horizontal_padding: 1

    table.head = @symbols.map do |symbol|
      SymbolSize.readable_symbol_name(symbol)
    end.push ''

    @diff.each do |commit, v|
      table.rows << @symbols.map do |symbol|
        add_sign(v[symbol])
      end.push(commit_name(commit))
    end

    1.upto(@symbols.size) { |i| table.align_column i, :right }
    puts table
  end

  def sort_sparse_changes
    return unless @sparse_changes

    @sparse_changes = @sparse_changes.sort_by do |k, v|
      order = SYMBOL_NAME_ORDER[k] || 0
      - order - v.first.first
    end

    @sparse_changes = @sparse_changes.to_h
  end

  def show_sparse_changes
    return if @sparse_changes.nil?
    return if @sparse_changes.empty?

    table = Text::Table.new vertical_boundary: '-',
                            horizontal_boundary: '|',
                            boundary_intersection: '+'

    table.head = %w[DELTA SYMBOL COMMIT]

    ret = 0
    @sparse_changes.each do |symbol, v|
      v.each do |delta, commit|
        next if delta.abs < MINIMAL_CHANGE / 2

        ret = 1 if delta.abs > MAXIMUM_CHANGE

        table.rows << [add_sign(delta), SymbolSize.readable_symbol_name(symbol), commit_name(commit)]
      end
    end

    table.align_column 1, :right
    puts table
    ret
  end

  def show_changes(commits)
    diff_commits(commits)
    changed_symbols
    reduce_overlap_symbols
    return unless any_significant_change?

    sort_symbols
    count_significant_changes
    split_sparse_symbols(1000) if @symbols.size >= 5 || @nr_significant_changes < @nr_significant_commits
    show_dense_changes
    sort_sparse_changes
    show_sparse_changes
  end
end
