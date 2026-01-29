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
