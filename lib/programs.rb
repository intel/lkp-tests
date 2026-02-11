#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'set'

module LKP
  class Programs
    PROGRAMS_ROOT = File.join(LKP_SRC, 'programs').freeze

    class << self
      def all_stats
        Dir["#{LKP_SRC}/stats/**/*"].map { |path| File.basename path } +
          Dir["#{PROGRAMS_ROOT}/*/parse"].map { |path| path.split('/')[-2] }
      end

      alias all_parser_names all_stats

      def all_tests
        Dir["#{LKP_SRC}/tests/**/*"].map { |path| File.basename path } +
          Dir["#{PROGRAMS_ROOT}/*/run"].map { |path| path.split('/')[-2] }
      end

      alias all_runner_names all_tests

      def all_tests_and_daemons
        all_tests + Dir["#{LKP_SRC}/daemon/**/*"].map { |path| File.basename path } +
          Dir["#{PROGRAMS_ROOT}/*/daemon"].map { |path| path.split('/')[-2] }
      end

      def all_tests_set
        @all_tests_set ||= Set.new(all_tests_and_daemons).freeze
      end

      def all_metas
        Dir["#{LKP_SRC}/tests/*.yaml"] + Dir["#{PROGRAMS_ROOT}/*/meta.yaml"]
      end

      def find_parser(program)
        [
          "#{PROGRAMS_ROOT}/#{program}/parse",
          "#{LKP_SRC}/stats/#{program}"
        ].find { |file| File.exist? file }
      end

      def find_runner(program)
        [
          "#{PROGRAMS_ROOT}/#{program}/run",
          "#{LKP_SRC}/tests/#{program}"
        ].find { |file| File.exist? file }
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
