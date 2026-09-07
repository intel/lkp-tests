require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Regression guard for tools/sort-files' etc/ sweep: an etc/sort-files-exclude
# entry (exact repo-root-relative file path, or a trailing-slash directory
# match anywhere under LKP_SRC) must be honored, while every other etc/ file
# still gets sorted. Exercises the real, checked-in etc/sort-files-exclude
# so this can never drift from what the exclusion list actually contains.
describe 'tools/sort-files etc/ exclusions' do
  let(:sort_files) { "#{LKP_SRC}/tools/sort-files" }

  # tools/sort-files reads etc/sort-files-exclude relative to $LKP_SRC --
  # seed a copy of the real exclusion list into the tmpdir fixture root so
  # the exclusion check itself is exercised, not just sort_file() in
  # isolation. seed_lib adds a real lib/ so LKP::Pattern.lines' require
  # chain resolves.
  def run_sort_files(file, fixture_root)
    seed_lib(fixture_root)
    FileUtils.mkdir_p(File.join(fixture_root, 'etc'))
    FileUtils.cp(
      File.join(LKP_SRC, 'etc', 'sort-files-exclude'),
      File.join(fixture_root, 'etc', 'sort-files-exclude')
    )
    Open3.capture3({ 'LKP_SRC' => fixture_root }, sort_files, file)
  end

  it 'leaves etc/makepkg.conf untouched (exact-path exclude entry)' do
    Dir.mktmpdir do |dir|
      etc_dir = File.join(dir, 'etc')
      FileUtils.mkdir_p(etc_dir)
      file = File.join(etc_dir, 'makepkg.conf')
      content = "zebra\nalpha\n"
      File.write(file, content)

      _, _, status = run_sort_files(file, dir)

      expect(status.success?).to be true
      expect(File.read(file)).to eq(content)
    end
  end

  it 'leaves files under a vendor/ directory untouched (trailing-slash exclude entry)' do
    Dir.mktmpdir do |dir|
      vendor_dir = File.join(dir, 'etc', 'vendor')
      FileUtils.mkdir_p(vendor_dir)
      file = File.join(vendor_dir, 'some-list')
      content = "zebra\nalpha\n"
      File.write(file, content)

      _, _, status = run_sort_files(file, dir)

      expect(status.success?).to be true
      expect(File.read(file)).to eq(content)
    end
  end

  it 'still sorts other etc files that are not excluded' do
    Dir.mktmpdir do |dir|
      etc_dir = File.join(dir, 'etc')
      FileUtils.mkdir_p(etc_dir)
      file = File.join(etc_dir, 'some-other-list')
      File.write(file, "zebra\nalpha\nalpha\n")

      _, _, status = run_sort_files(file, dir)

      expect(status.success?).to be true
      expect(File.read(file)).to eq("alpha\nzebra\n")
    end
  end
end
