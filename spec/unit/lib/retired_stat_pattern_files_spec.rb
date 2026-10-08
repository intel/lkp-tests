require 'spec_helper'
require 'open3'

# etc/failure, etc/pass and etc/skip were retired in favor of
# etc/stat-classifier.yml, which StatClassifier is the single reader of.
# Anything that still opens them would classify stats by a second, stale rule
# set (lib/ktest-bisect.sh once did, and disagreed with Ruby), or fail outright
# on the missing file.
describe 'retired stat pattern files' do
  %w[failure pass skip].each do |name|
    it "has no etc/#{name}" do
      expect(File.exist?("#{LKP_SRC}/etc/#{name}")).to be false
    end
  end

  it 'is not referenced by any script or library' do
    dirs = %w[bin sbin lib programs tools kbuild distro jobs stats monitors setup daemon].map { |dir| "#{LKP_SRC}/#{dir}" }.select { |dir| File.directory?(dir) }
    # (etc|ETC)/<name> not followed by a longer name, so /etc/passwd and
    # e.g. etc/skip-list do not count
    pattern = '(etc|ETC)/(failure|pass|skip)([^-_.a-zA-Z0-9]|$)'

    out, _err, = Open3.capture3('grep', '-rIlE', pattern, *dirs)

    expect(out.split("\n")).to be_empty
  end
end
