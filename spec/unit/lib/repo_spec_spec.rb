require 'fileutils'
require 'spec_helper'
require "#{LKP_SRC}/lib/lkp_tmpdir"
require "#{LKP_SRC}/lib/repo_spec"

describe RepoSpec do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('repo-spec-')
    @lkp_src = @tmp_dir.to_s

    FileUtils.mkdir_p("#{@lkp_src}/repo/linux")
    FileUtils.mkdir_p("#{@lkp_src}/repo/dpdk")

    File.write("#{@lkp_src}/repo/linux/DEFAULTS", <<~YAML)
      default_lkp_mail_cc: oe-lkp@lists.linux.dev
    YAML

    File.write("#{@lkp_src}/repo/linux/linux", <<~YAML)
      url: https://git.example.com/linux.git
    YAML

    File.write("#{@lkp_src}/repo/linux/linus", <<~YAML)
      url: https://git.example.com/torvalds/linux.git
      owner: Linus Torvalds <torvalds@linux-foundation.org>
    YAML

    File.write("#{@lkp_src}/repo/linux/acpi", <<~YAML)
      url: https://git.example.com/lenb/linux.git
      integration_testing_branches: next
      owner: Len Brown <len.brown@intel.com>
      maintained_subsystems:
      - intel_idle
    YAML

    File.write("#{@lkp_src}/repo/linux/internal-acpi", <<~YAML)
      url: https://git.example.com/internal/lenb-linux.git
      owner: Len Brown <len.brown@intel.com>
    YAML

    File.write("#{@lkp_src}/repo/dpdk/dpdk", <<~YAML)
      url: https://git.example.com/dpdk/dpdk.git
    YAML
  end

  before do
    stub_const('LKP_SRC', @lkp_src)
  end

  after(:all) do
    @tmp_dir.clean!
  end

  describe '#initialize' do
    it "raises when the named repo spec doesn't exist" do
      expect { described_class.new('doesnotexist') }.to raise_error(RuntimeError, /can't find repo spec/)
    end

    it 'accepts an absolute spec path directly' do
      spec = described_class.new("#{@lkp_src}/repo/linux/acpi")
      expect(spec['name']).to eq 'acpi'
    end
  end

  describe '#[]' do
    it 'merges DEFAULTS under project-specific keys without overriding them' do
      spec = described_class.new('acpi')
      expect(spec['owner']).to eq 'Len Brown <len.brown@intel.com>'
      expect(spec['default_lkp_mail_cc']).to eq 'oe-lkp@lists.linux.dev'
    end

    it 'derives project from the containing directory' do
      expect(described_class.new('acpi')['project']).to eq 'linux'
      expect(described_class.new('dpdk')['project']).to eq 'dpdk'
    end

    it 'marks a spec whose name matches its project as upstream' do
      spec = described_class.new('linux')
      expect(spec['upstream']).to be true
      expect(spec['fetch_tags']).to be true
      expect(spec['git_am_branch']).to eq 'master'
      expect(spec['maintained_files']).to eq '*'
    end

    it 'does not mark a non-matching name as upstream' do
      expect(described_class.new('acpi')['upstream']).to be_nil
    end
  end

  describe '#internal?' do
    it 'is true for a name prefixed with internal-' do
      expect(described_class.new('internal-acpi').internal?).to be true
    end

    it 'is false otherwise' do
      expect(described_class.new('acpi').internal?).to be false
    end
  end

  describe '#linux?' do
    it "is true when the spec's project is linux" do
      expect(described_class.new('acpi').linux?).to be true
    end

    it 'is false for a different project' do
      expect(described_class.new('dpdk').linux?).to be false
    end
  end

  describe '#git_am_branches' do
    it 'combines git_am_branch with integration_testing_branches' do
      expect(described_class.new('acpi').git_am_branches).to eq ['next']
    end

    it "defaults to the upstream 'master' branch when unset" do
      expect(described_class.new('linux').git_am_branches).to eq ['master']
    end
  end

  describe '#git_am_branch' do
    it 'returns the first git_am_branch' do
      expect(described_class.new('acpi').git_am_branch).to eq 'next'
    end
  end

  describe '.exist?' do
    it 'returns a path for a known repo name' do
      expect(described_class.exist?('acpi')).to include('repo/linux/acpi')
    end

    it 'returns nil for an unknown repo name' do
      expect(described_class.exist?('doesnotexist')).to be_nil
    end
  end

  describe '.all' do
    it 'loads every repo spec under repo/*/*, excluding DEFAULTS' do
      names = described_class.all.map { |spec| spec['name'] }
      expect(names).to contain_exactly('linux', 'linus', 'acpi', 'internal-acpi', 'dpdk')
    end
  end

  describe '.normalize_url' do
    it 'strips the scheme and a trailing .git suffix' do
      expect(described_class.normalize_url('https://git.example.com/torvalds/linux.git'))
        .to eq 'git.example.com/torvalds/linux'
    end
  end

  describe '.url_to_spec' do
    it 'finds the repo spec whose url normalizes to the same value' do
      spec = described_class.url_to_spec('https://git.example.com/torvalds/linux.git')
      expect(spec['remote']).to eq 'linus'
    end

    it "excludes 'linux' itself since it duplicates to linus" do
      expect(described_class.url_to_spec('https://git.example.com/linux.git')).to be_nil
    end
  end

  describe '.url_to_remote' do
    it 'returns just the remote name for a matching url' do
      expect(described_class.url_to_remote('https://git.example.com/torvalds/linux.git')).to eq 'linus'
    end

    it 'returns nil when no spec matches' do
      expect(described_class.url_to_remote('https://git.example.com/nope.git')).to be_nil
    end
  end

  describe '.remotes_to_specs' do
    it 'indexes every repo spec by its remote name' do
      remotes = described_class.remotes_to_specs
      expect(remotes['acpi']['project']).to eq 'linux'
      expect(remotes['dpdk']['project']).to eq 'dpdk'
    end
  end

  describe '.maintained_subsystems_to_specs' do
    it 'groups repo specs by maintained subsystem' do
      by_subsystem = described_class.maintained_subsystems_to_specs
      expect(by_subsystem['intel_idle'].map { |spec| spec['remote'] }).to eq ['acpi']
    end

    it 'returns an empty array for a subsystem with no maintainer' do
      expect(described_class.maintained_subsystems_to_specs['no-such-subsystem']).to eq []
    end
  end

  describe '.git_tree_owner?' do
    it 'allow-lists well-known upstream maintainers regardless of branch' do
      expect(described_class.git_tree_owner?('anything/master', 'Linus Torvalds')).to be true
    end

    it "checks the branch remote's repo spec owner otherwise" do
      expect(described_class.git_tree_owner?('acpi/next', 'Len Brown <len.brown@intel.com>')).to be true
    end

    it "returns false when the committer isn't in the resolved spec's owner" do
      expect(described_class.git_tree_owner?('acpi/next', 'Someone Else <else@example.com>')).to be false
    end

    it 'returns false when the branch remote has no known repo spec' do
      expect(described_class.git_tree_owner?('doesnotexist/next', 'Someone <else@example.com>')).to be false
    end

    it 'returns false when branch or committer is nil' do
      expect(described_class.git_tree_owner?(nil, 'Linus Torvalds')).to be false
      expect(described_class.git_tree_owner?('linus/master', nil)).to be false
    end
  end
end
