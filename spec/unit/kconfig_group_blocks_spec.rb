require 'spec_helper'
require "#{LKP_SRC}/lib/erb"

# Any programs/<suite>/include file that uses the `% if`/`% elsif` ERB
# pattern for its need_kconfig: section gets two checks here, fully dynamic
# (no suite names hardcoded, so a newly added suite using this convention is
# automatically covered the next time this spec runs). Mirrors the parsing
# logic in lkp-core's .agents/skills/lkp-tunetest/scripts/kconfig-block-tool
# -- keep the two in sync if the condition forms recognized there change.
#
# Recognized condition forms: `___.<field> == "value"`, `___.<field> =~
# /regex/`, and `job['<field>'] == "value"`. A condition that ORs multiple
# clauses together (e.g. `___.class == "security" || ___.test ==
# "apparmor"`) is "compound" -- there is no single unambiguous name for it,
# so it is excluded from the alphabetical-order check (the chain is split
# into runs at each compound block, each run checked independently) but is
# still covered by the ERB-render check.
#
# 1. Each run of non-compound %if/%elsif blocks is in strict alphabetical
#    order. (Catches drift like the ftrace/hid blocks that ended up
#    appended after a batch of unrelated net/* additions in
#    kselftests-bpf/include, or a %if/%elsif chain that was never sorted
#    at all, like kselftests/include or blktests/include.)
#
# 2. The ERB template renders cleanly (no exception) for every block,
#    using the exact production expand_erb helper. The context always
#    supplies every field referenced anywhere in the file (not just the
#    field under test) so a compound condition's short-circuit `||` never
#    hits an unrelated KeyError from Hashugar.
#
# Deliberately scoped to start scanning after the last `need_kconfig:` line:
# some include files (e.g. kselftests) also carry an unrelated single-branch
# chain under a different key (need_kernel_version:) that must not be
# merged into the need_kconfig: chain being checked here.
describe 'kconfig %if/%elsif blocks' do
  class << self
    def cond_re
      /(?:___\.(\w+)|job\[['"](\w+)['"]\])\s*(?:==\s*"([^"]+)"|=~\s*\/([^\/]+)\/)/
    end

    def regex_bare_name_re
      /^\^?([\w-]+)/
    end

    def extract_condition(cond_text)
      first_clause = cond_text.split('||').first
      m = cond_re.match(first_clause)
      return nil unless m

      kind = m[1] ? :dunder : :job
      field = m[1] || m[2]
      name = if m[4]
               bare = regex_bare_name_re.match(m[4])
               bare ? bare[1] : m[4]
             else
               m[3]
             end
      Struct.new(:kind, :field, :name, :compound).new(kind, field, name, cond_text.include?('||'))
    end

    def all_fields(marker_lines)
      fields = []
      marker_lines.each do |line|
        line.scan(cond_re) do |dunder_field, job_field, *_rest|
          fields << [:dunder, dunder_field] if dunder_field
          fields << [:job, job_field] if job_field
        end
      end
      fields.uniq
    end

    def condition_blocks(content)
      lines = content.lines
      scan_start = 0
      lines.each_with_index { |line, i| scan_start = i + 1 if line.strip == 'need_kconfig:' }

      marker_lines = lines[scan_start..].select { |l| l.strip.start_with?('% if', '% elsif') }
      blocks = marker_lines.filter_map do |line|
        cond_text = line.strip.sub(/^%\s*(?:if|elsif)\s+/, '')
        extract_condition(cond_text)
      end
      [blocks, all_fields(marker_lines)]
    end

    def build_context(fields)
      dunder = {}
      top = {}
      fields.each do |kind, field|
        target = kind == :dunder ? dunder : top
        target[field] = 'placeholder'
      end
      top['___'] = dunder unless dunder.empty?
      top
    end
  end

  includes = Dir["#{LKP_SRC}/programs/*/include"].select { |f| File.file?(f) }

  includes.each do |file|
    content = File.read(file)
    blocks, fields = condition_blocks(content)
    next if blocks.empty?

    suite = File.basename(File.dirname(file))

    describe "#{suite}/include" do
      it 'keeps each run of non-compound %if/%elsif blocks in alphabetical order' do
        runs = blocks.slice_when { |a, b| a.compound || b.compound }
                     .map { |r| r.reject(&:compound).map(&:name) }
        expect(runs).to all(satisfy('be sorted') { |run| run == run.sort })
      end

      blocks.each do |block|
        label = block.name.to_s.dup
        label << ' (compound condition)' if block.compound

        context = build_context(fields)
        if block.kind == :dunder
          context['___'][block.field] = block.name
        else
          context[block.field] = block.name
        end

        it "renders the ERB template cleanly for #{block.field} '#{label}'" do
          expect { expand_erb(content, context) }.not_to raise_error
        end
      end
    end
  end
end

# `need_kconfig:` must have a blank line before it whenever it is not the
# file's first line (e.g. something like `initrds+:` or
# `need_kernel_version:` precedes it) -- same visual-separation rationale as
# the blank line required before every `% elsif`. This applies to every
# programs/*/include file, %if-based or flat, with zero known exceptions.
describe 'kconfig need_kconfig: formatting' do
  includes = Dir["#{LKP_SRC}/programs/*/include"].select { |f| File.file?(f) }

  includes.each do |file|
    lines = File.read(file).lines.map(&:chomp)
    idx = lines.index { |l| l.strip == 'need_kconfig:' }
    next if idx.nil? || idx.zero?

    suite = File.basename(File.dirname(file))

    it "#{suite}/include has a blank line before need_kconfig:" do
      expect(lines[idx - 1].strip).to eq('')
    end
  end
end

# Most programs/*/include files have no %if/%elsif chain at all -- just a
# single flat need_kconfig: list. The order of entries in these files has
# NO semantic effect on the kernel build: the entries become a kconfig
# fragment applied via `make olddefconfig`, which resolves all `depends on`/
# `select` relationships automatically regardless of the order they appear.
# The standard is therefore plain alphabetical order for all flat files.
#
# kconfig-block-tool sort --group '<flat>' respects `#`-comment lines as
# sort barriers (same as for %if blocks), so files whose comment lines
# structure the list into named subsections (rcutorture/rcuscale/rcurefscale
# with per-commit `# <sha> (<description>)` groups, locktorture with
# per-error-message comments) get their entries sorted *within* each
# comment-delimited run -- but those runs span different topics and their
# combined entry list is not globally alphabetical. These are the only valid
# exemptions: the comments make the file structurally non-flat, so a
# global alphabetical check on the flattened entry list would be a false
# positive.
#
# All other "dependency chain" reasoning is invalid: make olddefconfig
# makes the include-file order irrelevant for correctness, and the
# "looks like a dependency chain" pattern was demonstrably wrong for
# at least ndctl (see git log). Every other flat file is just sorted now.
FLAT_KCONFIG_ORDER_EXEMPTIONS = {
  'locktorture' => 'comment-divided groups (per-error-message # comments act as sort barriers); entries sorted within each group via kconfig-block-tool',
  'rcurefscale' => 'comment-divided groups (per-commit # sha (description) comments act as sort barriers); entries sorted within each group',
  'rcuscale' => 'comment-divided groups (per-commit # sha (description) comments act as sort barriers); entries sorted within each group',
  'rcutorture' => 'comment-divided groups (per-commit # sha (description) comments act as sort barriers); entries sorted within each group'
}.freeze

describe 'kconfig flat need_kconfig: list order' do
  class << self
    def flat_entries(content)
      lines = content.lines
      scan_start = nil
      lines.each_with_index { |line, i| scan_start = i + 1 if line.strip == 'need_kconfig:' }
      return nil if scan_start.nil?
      return nil if lines[scan_start..].any? { |l| l.strip.start_with?('% if', '% elsif') }

      end_idx = lines.length
      lines[scan_start..].each_with_index do |line, offset|
        next unless line =~ /^[A-Za-z_][\w.+-]*:/

        end_idx = scan_start + offset
        break
      end

      entries = []
      lines[scan_start...end_idx].each do |line|
        m = /^-\s+([A-Za-z0-9_]+)\b/.match(line)
        entries << m[1] if m
      end
      entries
    end
  end

  includes = Dir["#{LKP_SRC}/programs/*/include"].select { |f| File.file?(f) }

  includes.each do |file|
    entries = flat_entries(File.read(file))
    next if entries.nil? || entries.size < 2

    suite = File.basename(File.dirname(file))
    next if FLAT_KCONFIG_ORDER_EXEMPTIONS.key?(suite)

    it "#{suite}/include keeps its flat need_kconfig: list in alphabetical order" do
      expect(entries).to eq(entries.sort)
    end
  end
end
