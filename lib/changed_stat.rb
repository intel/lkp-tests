#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'ostruct'
require "#{LKP_SRC}/lib/cache"
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/lkp_git"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/result"
require "#{LKP_SRC}/lib/stat_bounds"
require "#{LKP_SRC}/lib/statistics"
require "#{LKP_SRC}/lib/yaml"

module LKP
  class ChangedStat
    class << self
      include Cacheable

      # Cached per (project, remote): a Git::Base object is expensive to
      # build (its own tag list/tag order/gcommit lookups are memoized on
      # the instance, see lib/git/cache.rb) and load_base_matrix runs this
      # lookup once per test result on a busy process-unite-queue daemon.
      def project_git(project, remote)
        Git.open(project:, remote:)
      end
      cache_method :project_git

      # b/c a git repo like GIT_ROOT_DIR/linux keeps changing, it is
      # possible that a cached Git::Base object's tag list was built before
      # a new release tag (e.g. v4.3) landed on disk, so
      # release_tag_order(version) can return nil for a tag that
      # git.gcommit(commit).last_release_tag itself just returned. Drop the
      # cached object so the next project_git call re-opens the repo and
      # rebuilds its tag list from current disk state.
      def refresh_project_git(project, remote)
        key = singleton_class.cache_key(self, :project_git, project, remote)
        singleton_class.cache_store(:project_git).delete(key)
        project_git(project, remote)
      end

      def load_release_matrix(matrix_file)
        JSON.parse_cached matrix_file
      rescue StandardError => e
        log_error e
        nil
      end

      def vmlinuz_dir(kconfig, compiler, commit)
        "#{KERNEL_ROOT}/#{kconfig}/#{compiler}/#{commit}"
      end

      def load_base_matrix_for_notag_project(git, rp, axis)
        base_commit = git.first_sha
        log_debug "#{git.project} doesn't have tag, use its first commit #{base_commit} as base commit"

        rp[axis] = base_commit
        base_matrix_file = "#{rp._result_root}/matrix.json"
        unless File.exist? base_matrix_file
          log_warn "#{base_matrix_file} doesn't exist."
          return
        end
        load_release_matrix(base_matrix_file)
      end

      def load_base_matrix(matrix_path, head_matrix, options) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        matrix_path = File.realpath matrix_path
        matrix_path = File.dirname matrix_path if File.file? matrix_path
        log_debug "matrix_path is #{matrix_path}"

        rp = ResultPath.new
        rp.parse_result_root matrix_path

        puts rp if ENV['LKP_VERBOSE']
        project = options['bisect_project'] || 'linux'
        axis = options['bisect_axis'] || 'commit'

        commit = rp[axis]
        matrix = {}
        tags_merged = []

        begin
          axis_branch_name =
            if axis == 'commit'
              options['branch']
            else
              options[axis.sub('commit', 'branch')]
            end
          remote = axis_branch_name.split('/')[0] if axis_branch_name

          log_debug "remote is #{remote}"
          git = project_git(project, remote)
        rescue StandardError => e
          log_error e
          return
        end

        return load_base_matrix_for_notag_project(git, rp, axis) if git.tag_names.empty?

        begin
          return unless git.commit_exist? commit

          version = nil
          is_exact_match = false
          version, is_exact_match = git.gcommit(commit).last_release_tag
          log_debug "project: #{project}, version: #{version}, is_exact_match: #{is_exact_match}"
        rescue StandardError => e
          log_error e
          return
        end

        # FIXME: remove it later; or move it somewhere in future
        if project == 'linux' && !version
          kconfig = rp['kconfig']
          compiler = rp['compiler']
          context_file = "#{vmlinuz_dir(kconfig, compiler, commit)}/context.yaml"
          version = nil
          if File.exist? context_file
            context = YAML.load_file context_file
            version = context['rc_tag']
            is_exact_match = false
          end
          unless version
            log_error "Cannot get base RC commit for #{commit}"
            return
          end
        end

        order = git.release_tag_order(version)
        unless order
          git = refresh_project_git(project, remote)
          version, is_exact_match = git.gcommit(commit).last_release_tag
          order = git.release_tag_order(version)

          # FIXME: rli9 after above change, below situation is not reasonable, keep it for debugging purpose now
          unless order
            log_error('unknown version matrix', version:, matrix_path:, options:)
            return
          end
        end

        cols = 0
        git.release_tags_with_order.each do |tag, o|
          break if tag == 'v4.16-rc7' # kbuild doesn't support to build kernel < v4.16
          next if o >  order
          next if o == order && is_exact_match
          next if is_exact_match && tag =~ /^#{version}-rc[0-9]+$/
          break if tag =~ /\.[0-9]+$/ && tags_merged.size >= 2 && cols >= 6

          rp[axis] = tag
          base_matrix_file = "#{rp._result_root}/matrix.json"
          unless File.exist? base_matrix_file
            rp[axis] = git.release_tags2shas[tag]
            next unless rp[axis]

            base_matrix_file = "#{rp._result_root}/matrix.json"
          end
          next unless File.exist? base_matrix_file

          log_debug "base_matrix_file: #{base_matrix_file}"
          rc_matrix = load_release_matrix base_matrix_file
          next unless rc_matrix

          add_stats_to_matrix(rc_matrix, matrix)
          tags_merged << tag

          options['base_matrixes'] ||= {}
          options['base_matrixes'][tag] = rc_matrix

          cols += (rc_matrix['stats_source'] || []).size
          break if tags_merged.size >= 3 && cols >= 9
          break if tag =~ /-rc1$/ && cols >= 3
        end

        if matrix.empty?
          log_debug "no release matrix was found: #{matrix_path}"
          nil
        elsif cols >= 3 ||
              (cols >= 1 && functional_test?(rp['testcase'])) ||
              head_matrix['last_state.is_incomplete_run'] ||
              head_matrix['dmesg.boot_failures'] ||
              head_matrix['stderr.has_stderr']
          log_debug "compare with release matrix: #{matrix_path} #{tags_merged}"
          options['good_commit'] = tags_merged.first
          matrix
        else
          log_debug "release matrix too small: #{matrix_path} #{tags_merged}"
          nil
        end
      end
    end

    attr_reader :cs, :options

    def initialize(stat, sorted_a, sorted_b, options)
      min_b, mean_b, max_b = min_mean_max sorted_b
      min_a, mean_a, max_a = min_mean_max sorted_a

      @cs = OpenStruct.new sorted_a: sorted_a, min_a: min_a, mean_a: mean_a, max_a: max_a,
                           sorted_b: sorted_b, min_b: min_b, mean_b: mean_b, max_b: max_b,
                           stat: stat
      @options = options
      options['gap_distance'] ||= 2
    end

    %w(sorted_a min_a mean_a max_a sorted_b min_b mean_b max_b stat).each do |name|
      define_method(name) do
        cs[name]
      end
    end

    def failure?
      @failure ||= options["force_#{stat}"] || StatClassifier.function_stat?(stat)
    end

    def latency?
      @latency ||= StatClassifier.latency_stat?(stat)
    end

    def change?
      if options['distance']
        if max_a.is_a?(Integer) && (min_a - max_b == 1 || min_b - max_a == 1)
          log_cause 'min_a - max_b == 1 || min_b - max_a == 1'
          log_debug "not cs | cs: #{cs}" if options['trace_cause'] == stat

          return false
        end

        if sorted_a.size < 3 || sorted_b.size < 3
          len_a = max_a - min_a
          len_b = max_b - min_b
          min_gap = [len_a, len_b].max * options['distance']

          return true if min_b - max_a > min_gap

          log_cause "NOT: min_b - max_a > min_gap (#{min_gap})"

          return true if min_a - max_b > min_gap

          log_cause "NOT: min_a - max_b > min_gap (#{min_gap})"
        else
          return true if min_b > max_a && (min_b - max_a) > (mean_b - mean_a) / options['gap_distance']

          log_cause "NOT: min_b > max_a && (min_b - max_a) > (mean_b - mean_a) / #{options['gap_distance']}"

          return true if min_a > max_b && (min_a - max_b) > (mean_a - mean_b) / options['gap_distance']

          log_cause "NOT: min_a > max_b && (min_a - max_b) > (mean_a - mean_b) / #{options['gap_distance']}"
        end
      else
        return true if min_b > mean_a && mean_b > max_a

        log_cause 'NOT: min_b > mean_a && mean_b > max_a'

        return true if min_a > mean_b && mean_a > max_b

        log_cause 'NOT: min_a > mean_b && mean_a > max_b'
      end

      log_debug "cs | cs: #{cs}" if options['trace_cause'] == stat
      false
    end

    def to_s
      cs.to_s
    end

    def log_cause(cause)
      return unless options['trace_cause'] == stat

      begin
        %w(sorted_a min_a mean_a max_a sorted_b min_b mean_b max_b stat).each do |name|
          cause = cause.gsub(name, "#{name} (#{eval name})")
        end
      rescue StandardError => e
        log_debug e.formatted_headline
      end

      log_debug "not cs | cause: #{cause}"
    end
  end
end
