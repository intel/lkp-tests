#!/usr/bin/env ruby

module Markdownable
  def md_heading(marker = '=')
    [self, marker * ((size + marker.size - 1) / marker.size)].join("\n")
  end

  def md_heading1
    md_heading
  end

  def md_heading2
    md_heading('-')
  end

  def md_list(marker = '* ')
    "#{marker}#{self}"
  end

  def md_lists(marker = '* ')
    split("\n", -1).map { |line| line.empty? ? line : line.md_list(marker) }.join("\n")
  end
end
