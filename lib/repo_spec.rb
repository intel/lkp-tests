#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'pathname'
require 'yaml'
require "#{LKP_SRC}/lib/assert"
require "#{LKP_SRC}/lib/lkp_path"

class RepoSpec
  def initialize(name)
    if Pathname.new(name).absolute?
      spec_path = name
      name = File.basename name
    else
      name = name.split('/').first
      spec_path = Dir[File.join(self.class.root_dir, '*', name)].first
    end

    @spec = load(name, spec_path)
  end

  def [](key)
    @spec[key]
  end

  def internal?
    !!(self['name'] =~ /^internal-/)
  end

  def linux?
    self['project'] == 'linux'
  end

  def load(name, spec_path)
    assert spec_path && File.exist?(spec_path), "can't find repo spec #{name} at #{spec_path}"

    spec = YAML.load_file(spec_path)
    assert spec, "invalid spec #{spec_path}"

    spec['name'] = name
    spec['remote'] = name
    spec['path'] = spec_path

    defaults_spec_path = File.join(File.dirname(spec_path), 'DEFAULTS')
    if File.exist? defaults_spec_path
      defaults_spec = YAML.load_file(defaults_spec_path)
      assert defaults_spec, "invalid defaults spec #{defaults_spec_path}"

      spec = defaults_spec.merge(spec)
    end

    project = File.basename(File.dirname(spec_path))
    spec['project'] ||= project
    assert !spec['project'].to_s.empty?, "empty project name #{spec_path}"

    spec['upstream'] = true if spec['project'] == name

    if spec['upstream']
      spec['fetch_tags'] = true
      spec['git_am_branch'] ||= 'master'
      spec['maintained_files'] ||= '*'
    end

    spec
  end

  def git_am_branches
    Array(self['git_am_branch']) + Array(self['integration_testing_branches'])
  end

  def git_am_branch
    git_am_branches.first
  end

  class << self
    def root_dir
      LKP::Path.src 'repo'
    end

    def exist?(name)
      Dir[File.join(root_dir, '*', name)].first
    end

    def all
      Dir[File.join(root_dir, '*', '*')]
        .grep_v(/DEFAULTS$/)
        .map { |spec_path| new(spec_path) }
    end

    def url_to_spec(url)
      urls_to_specs[normalize_url(url)]
    end

    def url_to_remote(url)
      spec = urls_to_specs[normalize_url(url)]
      spec && spec['remote']
    end

    def urls_to_specs
      all.select { |repo_spec| repo_spec['url'] }
         .reject { |repo_spec| repo_spec['name'] =~ /^(linux-review|internal-linux-review|linux-devel|internal-devel|linux)$/ } # linux duplicates to linus
         .to_h { |repo_spec| [normalize_url(repo_spec['url']), repo_spec] }
         .merge('internal_merge_and_test_tree' => all.find { |repo_spec| repo_spec['name'] == 'linux-devel' })
    end

    def remotes_to_specs
      all.select { |repo_spec| repo_spec['remote'] }
         .to_h { |repo_spec| [repo_spec['remote'], repo_spec] }
    end

    def maintained_subsystems_to_specs
      spec_hash = Hash.new { |h, k| h[k] = [] }
      all.select { |repo_spec| repo_spec['maintained_subsystems'] }.each do |repo_spec|
        repo_spec['maintained_subsystems'].each { |subsystem| spec_hash[subsystem] << repo_spec }
      end
      spec_hash
    end

    def normalize_url(url)
      url.partition('://').last.chomp('.git')
    end
  end
end
