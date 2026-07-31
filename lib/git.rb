#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'git'
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/git/author"
require "#{LKP_SRC}/lib/git/base"
require "#{LKP_SRC}/lib/git/cache"
require "#{LKP_SRC}/lib/git/lib"
require "#{LKP_SRC}/lib/git/object"

module Git
  class << self
    # Mark one or more directories (or every directory, with '*') as a
    # git safe.directory for the current process, via the GIT_CONFIG_*
    # environment variables git itself reads. Every subsequent git
    # invocation in this process -- including the gem's own internal
    # worktree-root check -- inherits this regardless of $HOME/UID.
    #
    # git >=2.35.2 refuses to operate on a repository not owned by the
    # current user ("detected dubious ownership") unless that repository
    # is explicitly marked safe. A caller whose own account differs from
    # the repository owner (e.g. a daemon running as a service account
    # against a checkout owned by a different account) hits this even
    # though the checkout itself is perfectly valid. Git.open/Git.init
    # already call this automatically for their own working_dir, so most
    # callers never need to call it directly; call it explicitly only
    # when working with a repo through some other path (raw `git`/`Git.bare`
    # shellouts, a second repo not opened via Git.open) that needs the
    # same treatment, scoped to only the directories actually needed (or
    # '*' when the caller cannot know its exact set of repos up front).
    #
    # example
    #    Git.mark_safe_directory(GIT_ROOT_DIR)
    #    Git.mark_safe_directory('*')
    def mark_safe_directory(*dirs)
      dirs.each_with_index do |dir, i|
        ENV["GIT_CONFIG_KEY_#{i}"] = 'safe.directory'
        ENV["GIT_CONFIG_VALUE_#{i}"] = dir
      end
      ENV['GIT_CONFIG_COUNT'] = dirs.size.to_s
    end

    # init a repository
    #
    # options
    #    :project     => 'project_name', default is linux
    #    :working_dir => 'work_tree_dir', mandatory parameter
    #    :repository  => '/path/to/alt_git_dir', default is '/working_dir/.git'
    #    :index       => '/path/to/alt_index_file', default is '/working_dir/.git/index'
    #    :remote      => 'remote_name', default is nil
    #
    # example
    #    Git.init(project: 'dpdk', working_dir: "#{GIT_ROOT_DIR}/dpdk")
    #
    alias orig_init init
    def init(options = {})
      options[:project] ||= 'linux'

      working_dir = options[:working_dir] || "#{GIT_ROOT_DIR}/#{options[:project]}"

      mark_safe_directory(working_dir)

      Git.orig_init(working_dir, options)
    end

    #
    # open an existing repository
    #
    alias orig_open open
    def open(options = {})
      options[:project] ||= 'linux'

      working_dir = options[:working_dir] || "#{GIT_ROOT_DIR}/#{options[:project]}"

      return if options[:may_not_exist] && !Dir.exist?(working_dir)

      # Any caller may run as an account that doesn't own $GIT_ROOT_DIR's
      # checkout, which git >=2.35.2 refuses to touch
      # unless marked safe -- see comment on mark_safe_directory above.
      mark_safe_directory(working_dir)

      Git.orig_open(working_dir, options)
    end

    def sha1_40?(commit)
      commit =~ /^[\da-f]{40}$/
    end

    def commit_name?(name)
      name =~ /^[\da-f~^]{7,}$/ || name =~ /^v\d+\.\d+/ || sha1_40?(name)
    end

    def normalize_url(url)
      url.partition('://').last.chomp('.git')
    end
  end
end
