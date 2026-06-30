require 'spec_helper'

# Extract the effective sort key from a 4-space-indented YAML list line.
# Handles both active entries ("    - item") and commented-out entries
# ("    # - item # optional inline comment"), returning the item name in
# both cases so the two kinds interleave correctly when sorted.
def xfstests_list_entry_name(line)
  line.match(/^    #\s+-\s+(\S+)/)&.captures&.first ||
    line.match(/^    -\s+(\S+)/)&.captures&.first
end

# Split raw file lines into groups of consecutive 4-space list entries.
# Each group boundary is any line that is not a list entry (key lines,
# blank lines, 2-space fs: items, etc.).
def xfstests_list_entry_groups(lines)
  groups = []
  current = []
  lines.each do |line|
    name = xfstests_list_entry_name(line)
    if name
      current << name
    else
      groups << current.dup if current.size > 1
      current = []
    end
  end
  groups << current if current.size > 1
  groups
end

describe 'xfstests job YAML test list ordering' do
  Dir.glob("#{LKP_SRC}/jobs/xfstests-*.yaml").each do |file|
    basename = File.basename(file)

    it "#{basename} test list entries are sorted by effective name" do
      groups = xfstests_list_entry_groups(File.readlines(file))
      expect(groups).to all be_sorted
    end
  end
end
