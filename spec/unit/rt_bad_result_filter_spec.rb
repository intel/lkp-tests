require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# Coverage for lkp-exec/rt's /result/bad filtering: a result archived to
# /result/bad/... must be hidden from the default listing (matching the
# pre-day-index-rewrite behavior, where a bad result never showed up under
# its recorded path at all) and only -b surfaces it, exclusively.
describe 'lkp-exec/rt bad-result filtering' do
  let(:script) { "#{LKP_SRC}/lkp-exec/rt" }
  # guaranteed to not exist on disk in any environment, so the legacy
  # stale-entry fallback (which checks `-e`) never promotes this to bad
  let(:good_line) { '/result/zz-spec-good-nonexistent-9f3c/params/tbox/rootfs.cgz/kconfig/gcc/commit/0/' }
  let(:bad_line) { '/result/bad/zz-spec-bad-nonexistent-9f3c/params/tbox/rootfs.cgz/kconfig/gcc/commit/0/' }

  def with_index_file(lines)
    Dir.mktmpdir('rt-bad-filter-spec-') do |paths_dir|
      index_dir = File.join(paths_dir, '2026-10')
      FileUtils.mkdir_p(index_dir)
      File.write(File.join(index_dir, '2026-10-06-testqueue'), lines.map { |line| "#{line}\n" }.join)

      yield(paths_dir)
    end
  end

  it 'hides the bad result by default and shows the good one' do
    with_index_file([good_line, bad_line]) do |paths_dir|
      out = Bash.run("#{script} -t #{paths_dir}")

      expect(out.lines.map(&:chomp)).to contain_exactly(good_line.chomp)
    end
  end

  it '-b shows only the bad result, excluding the good one' do
    with_index_file([good_line, bad_line]) do |paths_dir|
      out = Bash.run("#{script} -t #{paths_dir} -b")

      expect(out.lines.map(&:chomp)).to contain_exactly(bad_line.chomp)
    end
  end
end
