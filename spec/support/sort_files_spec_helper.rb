require 'fileutils'

# LKP::Pattern.lines (etc/sort-files-exclude reading) pulls in
# lib/lkp_pattern_ext.rb's full require chain, so a fixture root needs a
# real lib/ alongside the file under test. Mirror this repo's lib/ in,
# without clobbering any fixture file the test already wrote.
def seed_lib(fixture_dir)
  preexisting = Dir.glob("#{fixture_dir}/lib/**/*", File::FNM_DOTMATCH)
                   .select { |p| File.file?(p) }
                   .map { |p| p.delete_prefix("#{fixture_dir}/") }

  Dir.glob("#{LKP_SRC}/lib/**/*", File::FNM_DOTMATCH).each do |src_path|
    next unless File.file?(src_path)

    relative = src_path.delete_prefix("#{LKP_SRC}/")
    next if preexisting.include?(relative)

    dest_path = File.join(fixture_dir, relative)
    FileUtils.mkdir_p(File.dirname(dest_path))
    FileUtils.cp(src_path, dest_path)
  end
end
