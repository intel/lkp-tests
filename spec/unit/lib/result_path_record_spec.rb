require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# Coverage for lib/result.sh's day-index path-record rewriters --
# clean_path_record_from_result_root() (genuine deletion, used by e.g.
# lkp-exec/_rm) and move_path_record_from_result_root() (rewrite in place,
# used by save_bad_result() when archiving a result to /result/bad/...).
# Both share a common rewrite_path_record_files() helper, so this also
# guards that refactor: each function must only ever touch the one
# day-index line that actually matches its target path.
describe 'lib/result.sh path record functions' do
  def with_index_file(lines)
    Dir.mktmpdir('result-sh-spec-') do |paths_dir|
      index_dir = File.join(paths_dir, '2026-10')
      FileUtils.mkdir_p(index_dir)
      index_file = File.join(index_dir, '2026-10-06-devel-hourly')
      File.write(index_file, lines.map { |line| "#{line}\n" }.join)

      yield(paths_dir, index_file)
    end
  end

  let(:target_root) { '/result/makepkg/params/tbox/debian.cgz/kconfig/gcc/commit/0' }
  let(:other_line) { '/result/other-suite/params/tbox/debian.cgz/kconfig/gcc/commit/0/' }

  it 'move_path_record_from_result_root rewrites only the matching line in place' do
    bad_root = '/result/bad/makepkg/params/tbox/debian.cgz/kconfig/gcc/commit/0'

    with_index_file(["#{target_root}/", other_line]) do |paths_dir, index_file|
      Bash.run(<<~SCRIPT)
        source #{LKP_SRC}/lib/result.sh
        KTEST_PATHS_DIR=#{paths_dir}
        move_path_record_from_result_root #{target_root} #{bad_root}
      SCRIPT

      expect(File.read(index_file)).to eq("#{bad_root}/\n#{other_line}\n")
    end
  end

  it 'clean_path_record_from_result_root drops only the matching line' do
    with_index_file(["#{target_root}/", other_line]) do |paths_dir, index_file|
      Bash.run(<<~SCRIPT)
        source #{LKP_SRC}/lib/result.sh
        KTEST_PATHS_DIR=#{paths_dir}
        clean_path_record_from_result_root #{target_root}
      SCRIPT

      expect(File.read(index_file)).to eq("#{other_line}\n")
    end
  end
end
