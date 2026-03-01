#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'set'

module LKP
  class Programs
    PROGRAMS_ROOT = File.join(LKP_SRC, 'programs').freeze

    class << self
      def collect_programs(lkp_src_pattern, programs_pattern, executable_only: false)
        lkp_files = lkp_src_pattern ? Dir["#{LKP_SRC}/#{lkp_src_pattern}"] : []
        prog_files = Dir["#{PROGRAMS_ROOT}/#{programs_pattern}"]

        if executable_only
          lkp_files.select! { |p| File.file?(p) && File.executable?(p) }
          prog_files.select! { |p| File.file?(p) && File.executable?(p) }
        end

        (lkp_files || []).map { |path| File.basename(path) } + (prog_files || []).map { |path| path.split('/')[-2] }
      end

      def find_executable(program, lkp_dir, *prog_names)
        candidates = prog_names.map { |n| "#{PROGRAMS_ROOT}/#{program}/#{n}" }
        candidates << "#{LKP_SRC}/#{lkp_dir}/#{program}" if lkp_dir
        candidates.find { |file| File.exist?(file) }
      end

      def all_stats
        collect_programs('stats/**/*', '*/parse')
      end

      alias all_parser_names all_stats

      def all_tests
        collect_programs(nil, '*/run')
      end

      alias all_runner_names all_tests

      def all_monitors
        collect_programs(nil, '*/{monitor,no-stdout-monitor,one-shot-monitor}', executable_only: true)
      end

      def all_setups
        collect_programs(nil, '*/setup', executable_only: true)
      end

      def all_daemons
        collect_programs(nil, '*/daemon', executable_only: true)
      end

      def all_tests_and_daemons
        all_tests + all_daemons
      end

      def all_tests_set
        @all_tests_set ||= Set.new(all_tests_and_daemons).freeze
      end

      def all_metas
        Dir["#{PROGRAMS_ROOT}/*/meta.yaml"]
      end

      def find_meta(program)
        [
          "#{PROGRAMS_ROOT}/#{program}/meta.yaml"
        ].find { |file| File.exist?(file) }
      end

      def find_parser(program)
        find_executable(program, 'stats', 'parse')
      end

      def find_setup(program)
        find_executable(program, nil, 'setup')
      end

      def find_monitor(program)
        find_executable(program, nil, 'monitor', 'no-stdout-monitor', 'one-shot-monitor')
      end

      def find_daemon(program)
        find_executable(program, nil, 'daemon')
      end

      def find_runner(program)
        find_executable(program, nil, 'run')
      end

      # program: turbostat, turbostat-dev
      def find_depends_file(program)
        candidates = ["#{LKP_SRC}/distro/depends/#{program}", "#{PROGRAMS_ROOT}/#{program}/pkg/depends"]
        candidates += ["#{PROGRAMS_ROOT}/#{program.sub(/-dev$/, '')}/pkg/depends-dev"] if program =~ /-dev$/

        candidates.find { |file| File.exist? file }
      end

      def find_pkg_dir(program)
        [
          "#{PROGRAMS_ROOT}/#{program}/pkg"
        ].find { |path| Dir.exist? path }
      end

      def find_program_dir(program)
        [
          "#{PROGRAMS_ROOT}/#{program}"
        ].find { |path| Dir.exist? path }
      end
    end
  end
end
