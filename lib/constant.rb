#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'etc'
require "#{LKP_SRC}/lib/run_env"

LKP_USER ||= ENV['LKP_USER'] || ENV['USER'] || Etc.getpwuid(Process.uid).name

DEVEL_HOURLY_KCONFIGS = %w(x86_64-rhel-7.6).freeze
LKP_DEFAULT_COMPILER = 'gcc-7'.freeze
GIT_ROOT_DIR = '/lkp/repo'.freeze

TESTCASE_AXIS_KEY = 'testcase'.freeze
COMMIT_AXIS_KEY = 'commit'.freeze
TBOX_GROUP_AXIS_KEY = 'tbox_group'.freeze

KERNEL_ROOT = '/pkg/linux'.freeze
KTEST_USER_GENERATED_DIR = '/lkp/user-generated'.freeze
KTEST_DATA_DIR = '/lkp/data'.freeze
KTEST_PATHS_DIR = '/lkp/paths'.freeze
RESULT_ROOT_DIR = '/lkp/result'.freeze
