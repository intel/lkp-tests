#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__, 2)

require 'git'

module Git
  class Base
    alias orig_initialize initialize

    attr_reader :project

    def initialize(options = {})
      orig_initialize(options)
      @project = options[:project]
      @remote = options[:remote] || @project
    end

    def project_spec
      $remotes ||= load_remotes

      $remotes[@remote] || $remotes["internal-#{@remote}"]
    end

    alias rev_parse revparse

    # add tag_names because Base::tags is slow to obtain all tag objects
    # FIXME consider to cache this method
    def tag_names
      lib.tag('-l').split("\n")
    end

    def commit_exist?(commit)
      command('rev-list', ['-1', commit])
    rescue StandardError
      false
    else
      true
    end

    def remote_exist?(remote)
      command('remote').split.include?(remote)
    end

    def branch_exist?(pattern)
      !command('branch', ['--list', '-a', pattern]).empty?
    end

    def branch_exist_in_remote?(remote_url, branch)
      command("ls-remote -h #{remote_url} #{branch}").split.include?("refs/heads/#{branch}")
    end

    def kernel_branch?(branch)
      return false unless command_lines('show', "#{branch}:").include?('Makefile')
      return false unless command('show', "#{branch}:Makefile").include?('KERNELRELEASE')

      true
    rescue StandardError
      false
    end

    def linux_last_release_tag_strategy(commit_sha)
      version = patch_level = sub_level = rc = nil

      command_lines('show', "#{commit_sha}:Makefile").each do |line|
        case line
        when /^VERSION *= *(\d+)/
          version = $1.to_i
        when /^PATCHLEVEL *= *(\d+)/
          patch_level = $1.to_i
        when /^SUBLEVEL *= *(\d+)/
          sub_level = $1.to_i
        when /^EXTRAVERSION *= *-rc(\d+)/
          rc = $1.to_i
        when /^NAME *= */
          break
        else
          next
        end
      end

      if version && version >= 2
        tag = "v#{version}.#{patch_level}"
        tag += ".#{sub_level}" if version == 2
        tag += "-rc#{rc}" if rc&.positive?

        [tag, false]
      else
        log_warn "version #{version.inspect} of #{commit_sha} is invalid"

        nil
      end
    end

    def commits_tags
      return @commits_tags if @commits_tags

      @commits_tags = {}
      command('show-ref', ['--tags']).each_line do |line|
        commit, tag = line.split ' refs/tags/'
        @commits_tags[commit] = tag.chomp if tag
      end

      @commits_tags
    end

    def heads_branches
      return @heads_branches if @heads_branches

      @heads_branches = {}
      command('show-ref').each_line do |line|
        commit, branch = line.split ' refs/remotes/'
        @heads_branches[commit] = branch.chomp if branch
      end

      @heads_branches
    end

    def release_tag_pattern
      log_warn "project_spec is nil, remote: #{@remote}, project: #{@project}" unless project_spec

      @release_tag_pattern ||= Regexp.new "^#{Array(project_spec['release_tag_pattern']).join('$|^')}$"
    end

    def release_tags
      @release_tags ||= tag_names.select { |tag_name| release_tag_pattern.match(tag_name) }
    end

    def release_tags_with_order
      unless @release_tags_with_order
        tags = sort_tags(release_tag_pattern, release_tags)
        @release_tags_with_order = tags.map.with_index { |tag, i| [tag, -i] }.to_h
      end

      @release_tags_with_order
    end

    def ordered_release_tags
      release_tags_with_order.keys
    end

    def ordered_official_release_tags
      release_tags_with_order.keys.grep(/^v[0-9]*\.[0-9]*(|\.[0-9]*)$/)
    end

    def latest_release_tag
      ordered_release_tags.first
    end

    def release_shas
      @release_shas ||= release_tags.map { |release_tag| command('rev-list', ['-1', release_tag]) }
    end

    def release_tags2shas
      unless @release_tags2shas
        tags = release_tags
        shas = release_shas

        @release_tags2shas = {}
        tags.each_with_index { |tag, i| @release_tags2shas[tag] = shas[i] }
      end

      @release_tags2shas
    end

    def release_shas2tags
      unless @release_shas2tags
        tags = release_tags
        shas = release_shas

        @release_shas2tags = {}
        shas.each_with_index { |sha, i| @release_shas2tags[sha] = tags[i] }
      end

      @release_shas2tags
    end

    def release_tag_order(tag)
      release_tags_with_order[tag]
    end

    def sort_commits(commits)
      scommits = commits.map(&:to_s)
      if scommits.size == 2
        r = command('rev-list', ['-n', '1', "^#{scommits[0]}", scommits[1]])
        scommits.reverse! if r.strip.empty?
      else
        scommits.sort! do |c1, c2|
          r = command('rev-list', ['-n', '1', "^#{c1}", c2])
          if r.strip.empty?
            1
          else
            -1
          end
        end
      end

      scommits.map { |sc| gcommit sc }
    end

    def first_sha
      command('rev-list --reverse HEAD |head -1')
    end

    def command(cmd, opts = [], redirect = '', chdir: true, &block)
      lib.command(cmd, opts, redirect, chdir: chdir, &block)
    end

    def command_lines(cmd, opts = [], redirect = '', chdir: true)
      lib.command_lines(cmd, opts, redirect, chdir: chdir)
    end
  end
end
