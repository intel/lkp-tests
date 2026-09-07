require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Regression guard for tools/sort-files' integration with
# tools/ktest/kconfig-block-tool: a programs/<suite>/include file
# (need_kconfig: YAML list, optionally wrapped in %if/%elsif ERB group
# blocks) must never be run through the plain whole-file `sort -f | uniq`
# used for flat list files elsewhere in tools/sort-files -- that would
# scramble the need_kconfig: header line and the ERB block markers.
# tools/sort-files must instead detect programs/<suite>/include paths and
# sort only the entries within each block/comment-delimited run.
describe 'tools/sort-files kconfig include-file integration' do
  let(:sort_files) { "#{LKP_SRC}/tools/sort-files" }

  # A standalone checkout of this repo never ships
  # tools/ktest/kconfig-block-tool, so exercise the pure-Ruby fallback sorter
  # via SORT_FILES_KCONFIG_FALLBACK=ruby -- the same env var this repo's own
  # Rakefile sets for its :sort task, and therefore the actual code path this
  # repo's own `rake sort` runs in practice.
  def run_sort_files(file, fixture_root, check: false)
    seed_lib(fixture_root)
    FileUtils.mkdir_p(File.join(fixture_root, 'etc'))
    FileUtils.cp(
      File.join(LKP_SRC, 'etc', 'sort-files-exclude'),
      File.join(fixture_root, 'etc', 'sort-files-exclude')
    )
    args = check ? [sort_files, '--check', file] : [sort_files, file]
    Open3.capture3({ 'LKP_SRC' => fixture_root, 'SORT_FILES_KCONFIG_FALLBACK' => 'ruby' }, *args)
  end

  it 'sorts a flat need_kconfig: list without disturbing surrounding YAML keys' do
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, 'programs', 'fake-suite')
      FileUtils.mkdir_p(suite_dir)
      file = File.join(suite_dir, 'include')
      File.write(file, <<~CONTENT)
        initrds+:
        - linux_perf

        need_kconfig:
        - TUN: m
        - CPU_SUP_INTEL: y
        - CONTIG_ALLOC: y
      CONTENT

      _, _, status = run_sort_files(file, dir)

      expect(status.success?).to be true
      expect(File.read(file)).to eq(<<~EXPECTED)
        initrds+:
        - linux_perf

        need_kconfig:
        - CONTIG_ALLOC: y
        - CPU_SUP_INTEL: y
        - TUN: m
      EXPECTED
    end
  end

  it 'sorts entries within each %if/%elsif block without reordering the blocks' do
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, 'programs', 'fake-erb-suite')
      FileUtils.mkdir_p(suite_dir)
      file = File.join(suite_dir, 'include')
      File.write(file, <<~CONTENT)
        need_kconfig:
        - GLOBAL_ENTRY: y

        % if ___.group == "bpf"
        - ZEBRA: y
        - ALPHA: y
        % elsif ___.group == "net"
        - NET_B: m
        - NET_A: m
        % end
      CONTENT

      _, _, status = run_sort_files(file, dir)

      expect(status.success?).to be true
      expect(File.read(file)).to eq(<<~EXPECTED)
        need_kconfig:
        - GLOBAL_ENTRY: y

        % if ___.group == "bpf"
        - ALPHA: y
        - ZEBRA: y
        % elsif ___.group == "net"
        - NET_A: m
        - NET_B: m
        % end
      EXPECTED
    end
  end

  it 'is idempotent on an already-sorted include file' do
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, 'programs', 'fake-suite')
      FileUtils.mkdir_p(suite_dir)
      file = File.join(suite_dir, 'include')
      sorted_content = <<~CONTENT
        need_kconfig:
        - CONTIG_ALLOC: y
        - CPU_SUP_INTEL: y
        - TUN: m
      CONTENT
      File.write(file, sorted_content)

      run_sort_files(file, dir)

      expect(File.read(file)).to eq(sorted_content)
    end
  end

  it 'leaves a non-include file (e.g. a depends file) using the plain whole-file sort' do
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, 'programs', 'fake-suite')
      FileUtils.mkdir_p(suite_dir)
      file = File.join(suite_dir, 'depends-ubuntu')
      File.write(file, "zlib1g\nbuild-essential\nautoconf\n")

      run_sort_files(file, dir)

      expect(File.read(file)).to eq("autoconf\nbuild-essential\nzlib1g\n")
    end
  end

  # Regression guard for a real incident: a built image silently never
  # shipped the kconfig-block-tool dependency tools/sort-files shells out
  # to by default (the tool-delegating path used whenever
  # SORT_FILES_KCONFIG_FALLBACK isn't set to 'ruby', e.g. a paired
  # infrastructure repo's own `rake sort` against a merged runtime tree).
  # Before this fix, that
  # missing dependency was swallowed: sort_file() called python3 with no
  # error check, so the include file was silently left unsorted and
  # tools/sort-files still exited 0, no error visible anywhere in CI.
  it 'fails loudly instead of silently leaving the file unsorted when kconfig-block-tool is missing' do
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, 'programs', 'fake-suite')
      FileUtils.mkdir_p(suite_dir)
      file = File.join(suite_dir, 'include')
      content = <<~CONTENT
        need_kconfig:
        - TUN: m
        - CPU_SUP_INTEL: y
        - CONTIG_ALLOC: y
      CONTENT
      File.write(file, content)

      seed_lib(dir)
      FileUtils.mkdir_p(File.join(dir, 'etc'))
      FileUtils.cp(File.join(LKP_SRC, 'etc', 'sort-files-exclude'), File.join(dir, 'etc', 'sort-files-exclude'))

      # Deliberately do NOT seed tools/ktest/kconfig-block-tool into dir,
      # and do NOT set SORT_FILES_KCONFIG_FALLBACK, simulating an LKP_SRC
      # tree that claims to ship the tool-delegating path but doesn't.
      _, stderr, status = Open3.capture3({ 'LKP_SRC' => dir }, sort_files, file)

      expect(status.success?).to be false
      expect(stderr).to include('kconfig-block-tool')
      expect(File.read(file)).to eq(content)
    end
  end

  # Regression guard: kconfig-block-tool's `sort-all` (no --apply) used to
  # print its "nothing to sort" notice only to stderr and return without
  # ever echoing the file's own lines to stdout, so sort_kconfig_include's
  # stdout-vs-original comparison always saw an empty string on one side.
  # Every already-sorted (or never-sortable) programs/<suite>/include file
  # with no %if/%elsif blocks and no flat need_kconfig: list was therefore
  # reported as needing a sort (--check exit 1) on every single run, even
  # though `rake sort` (apply mode) itself never actually modified it.
  it 'reports --check success (no sort needed) for an include file with no need_kconfig: section' do
    Dir.mktmpdir do |dir|
      suite_dir = File.join(dir, 'programs', 'fake-suite')
      FileUtils.mkdir_p(suite_dir)
      file = File.join(suite_dir, 'include')
      content = <<~CONTENT
        initrds+:
        - linux_headers
      CONTENT
      File.write(file, content)

      stdout, _, status = run_sort_files(file, dir, check: true)

      expect(stdout).not_to include('would sort')
      expect(status.success?).to be true
      expect(File.read(file)).to eq(content)
    end
  end
end
