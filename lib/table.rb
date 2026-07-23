require 'text-table'

def longest_prefix(strings)
  prefix = strings[0].dup
  strings.each do |s|
    next unless prefix != s

    until prefix.empty?
      break if prefix == s[0...prefix.length] && prefix[-1] == '/'

      prefix.chop!
    end
  end
  prefix
end

def longest_suffix(strings)
  suffix = strings[0].dup
  strings.each do |s|
    next unless suffix != s

    until suffix.empty?
      break if suffix == s[-suffix.length...s.length] && suffix[0] == '/'

      suffix[0] = ''
    end
  end
  suffix
end

def to_table(matrix, head)
  table = Text::Table.new vertical_boundary: '-',
                          horizontal_boundary: '|',
                          boundary_intersection: '+'
  table.head = ['', *head]
  matrix.each do |k, v|
    v << '' while v.size < head.size
    table.rows << [k, *v]
  end
  table
end

def to_rtable(matrix, head)
  table = Text::Table.new vertical_boundary: '-',
                          horizontal_boundary: '|',
                          boundary_intersection: '+'
  table.head = [*head, '']
  matrix.each do |k, v|
    v << '' while v.size < head.size
    table.rows << [*v, k]
  end
  table
end
