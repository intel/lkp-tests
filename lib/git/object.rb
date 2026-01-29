#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__, 2)

require 'git'

module Git
  class Object
    class Commit
      alias orig_initialize initialize
      PGP_SIGNATURE = '-----END PGP SIGNATURE-----'.freeze

      def initialize(base, sha, init = nil)
        orig_initialize(base, sha, init)
        # this is to convert non sha1 40 such as tag name to corresponding commit sha
        # otherwise Object::AbstractObject uses @base.lib.revparse(@objectish) to get sha
        # which sometimes is not as expected when we give a tag name
        self.objectish = command('rev-list', ['-1', objectish]) unless Git.sha1_40?(objectish)
      end

      def project
        @base.project
      end

      def subject
        raw_message = message
        raw_message = raw_message.split(PGP_SIGNATURE).last.sub(/^\s+/, '') if raw_message.include?(PGP_SIGNATURE)
        raw_message.split("\n").first
      end

      def tags
        @tags ||= command("tag --points-at #{sha} | grep -v ^error:").split
      end

      def parent_shas
        @parent_shas ||= parents.map(&:sha)
      end

      def show(content)
        command_lines('show', "#{sha}:#{content}")
      end

      def tag
        @tag ||= release_tag || tags.first
      end

      def release_tag
        unless @release_tag
          release_tags_with_order = @base.release_tags_with_order
          @release_tag = tags.find { |tag| release_tags_with_order.include? tag }
        end

        @release_tag
      end

      #
      # if commit has a version tag, return it directly
      # otherwise checkout commit and get latest version from Makefile.
      #
      def last_release_tag
        return [release_tag, true] if release_tag

        if project == 'linux' && !@base.project_spec['use_customized_release_tag_pattern']
          @base.linux_last_release_tag_strategy(sha)
        else
          last_release_sha = command("rev-list #{sha} | grep -m1 -Fx \"#{@base.release_shas.join("\n")}\"").chomp

          last_release_sha.empty? ? nil : [@base.release_shas2tags[last_release_sha], false]
        end
      end

      def base_rc_tag
        # rli9 FIXME: bad smell here to distinguish linux by case/when
        commit = case project
                 when 'linux'
                   @base.gcommit("#{sha}~") if committer.name == 'Linus Torvalds'
                 end

        commit ||= self

        tag, _is_exact_match = commit.last_release_tag
        tag
      end

      # v3.11     => v3.11
      # v3.11-rc1 => v3.10
      def last_official_release_tag
        tag, _is_exact_match = last_release_tag
        return tag unless tag =~ /-rc/

        order = @base.release_tag_order(tag)
        tag_with_order = @base.release_tags_with_order.find { |tag, o| o <= order && tag !~ /-rc/ }

        tag_with_order ? tag_with_order[0] : nil
      end

      # v3.11     => v3.10
      # v3.11-rc1 => v3.10
      def prev_official_release_tag
        tag, is_exact_match = last_release_tag

        order = @base.release_tag_order(tag)
        tag_with_order = @base.release_tags_with_order.find do |tag, o|
          next if o > order
          next if o == order && is_exact_match

          tag !~ /-rc/
        end

        tag_with_order ? tag_with_order[0] : nil
      end

      # v3.12-rc1 => v3.12
      # v3.12     => v3.13
      def next_official_release_tag
        tag = release_tag
        return unless tag

        order = @base.release_tag_order(tag)
        return unless order

        @base.release_tags_with_order.reverse_each do |tag, o|
          next if o <= order

          return tag unless tag =~ /-rc/
        end

        nil
      end

      def next_release_tag
        tag = release_tag
        return unless tag

        order = @base.release_tag_order(tag)
        @base.release_tags_with_order.reverse_each do |tag, o|
          next if o <= order

          return tag
        end

        nil
      end

      def linux_next_version
        show('localversion-next').first.sub(/^-/, '')
      rescue Git::GitExecuteError
        # ignore error to return nil
        nil
      end

      def version_tag
        tag, is_exact_match = last_release_tag

        tag += '+' if tag && !is_exact_match
        tag
      end

      RE_BY_CC = /(?:by|[Cc][Cc]):\s*([^<\r\n]+) <([^>\r\n]+@[^>\r\n]+)>\s*$/

      def by_cc
        m = message
        pos = 0
        res = []
        while (mat = RE_BY_CC.match(m, pos))
          res.push Git::Author.new("#{mat[1]} <#{mat[2]}> #{Time.now.to_i} ")
          pos = mat.end 0
        end
        res
      end

      def reachable_from?(branch)
        branch = @base.gcommit(branch)
        r = command('rev-list', ['-n', '1', sha, "^#{branch.sha}"])
        r.strip.empty?
      end

      def merged_by
        return @merged_by if @merged_by

        base_rc_tag = self.base_rc_tag

        @merged_by = @base.ordered_release_tags
                          .reverse
                          .drop_while { |tag| tag != base_rc_tag }
                          .drop(1)
                          .find { |tag| reachable_from?(tag) }
      end

      def relative_commit_date
        command("log -n1 --format=format:'%cr' #{sha}")
      end

      def prev_official_release
        @base.gcommit(prev_official_release_tag)
      end

      def last_release
        @base.gcommit(last_release_tag.first)
      end

      alias committed_release last_release

      def merged_release
        merged_by && @base.gcommit(merged_by)
      end

      def abbr
        tag || sha[0..11]
      end

      def files
        command("diff-tree --no-commit-id --name-only -r #{sha}").split
      end

      def fixed?(branch)
        short_sha = sha[0..7]
        !command("log --grep 'Fixes:' #{sha}..#{branch} | grep \"Fixes: #{short_sha}\"").empty?
      end

      def fixed_by(branch)
        command_lines("log --grep='^Fixes: #{sha[0..7]}' -P --oneline --format='%H' #{sha}..#{branch}").map { |commit| @base.gcommit(commit) }
      end

      def reverted?(branch)
        reverted_subject = "Revert \\\"#{subject.gsub(/(["\[\]])/, '\\\\\1')}\\\""
        !command("log --format=%s #{sha}..#{branch} | grep -x -m1 \"#{reverted_subject}\"").empty?
      end

      def exist_in?(branch)
        # $ git merge-base --is-ancestor 071e7d275bd4abeb7d75844020b05bd77032ac62 origin/master
        # fatal: Not a valid commit name 071e7d275bd4abeb7d75844020b05bd77032ac62
        command("merge-base --is-ancestor #{sha} #{branch} 2>/dev/null; echo $?").to_i.zero?
      end

      def mainline?
        return @mainline unless @mainline.nil?

        @mainline = exist_in? 'linus/master'
      end

      def merge?
        parents.many?
      end

      def patch_id
        return @patch_id if @patch_id

        @patch_id = command("show #{sha} 2>/dev/null | git patch-id --stable").split.first
      end

      def changes(base_commit = nil)
        # $ diff --name-only c15cc235b744~ c15cc235b744
        # drivers/block/sunvdc.c
        base_commit ||= "#{sha}~"

        cmd = "diff --name-status #{base_commit} #{sha}"
        command_lines(cmd)
      end

      def ancestor?(commit)
        # $ git merge-base --is-ancestor 3e38e0aaca9eafb12b1c4b731d1c10975cbe7974 5f0b06da5cde3f0a613308b89f0afea678559fdf
        # $ echo $?
        # 0
        # $ git rev-list v5.8..5f0b06da5cde3f0a613308b89f0afea678559fdf | grep 3e38e0aaca9eafb12b1c4b731d1c10975cbe7974
        # 3e38e0aaca9eafb12b1c4b731d1ic10975cbe7974
        @ancestors ||= {}
        @ancestors[commit] if @ancestors.key? commit

        @ancestors[commit] = exist_in?(commit)
      end

      def command(cmd, opts = [], redirect = '', chdir: true, &block)
        @base.command(cmd, opts, redirect, chdir: chdir, &block)
      end

      def command_lines(cmd, opts = [], redirect = '', chdir: true)
        @base.command_lines(cmd, opts, redirect, chdir: chdir)
      end
    end

    class Tag
      def commit
        @base.gcommit(@base.command('rev-list', ['-1', @name]))
      end
    end
  end
end
