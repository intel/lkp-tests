require 'fileutils'
require 'spec_helper'
require 'tmpdir'
require 'yaml'
require "#{LKP_SRC}/lib/bash"

# jobs/kselftests/kselftests-bpf.yaml's "drivers" job group has no test:
# filter, so lib/tests/kselftests.sh's prepare_for_selftest_mfs recursively
# discovers every Makefile under tools/testing/selftests/drivers/. A
# handful of genuinely slow subgroups (currently drivers/net,
# drivers/net/bonding, drivers/net/hw, drivers/net/netdevsim) are split
# into their own job group: entries instead, and prepare_for_selftest_mfs
# excludes those Makefiles when $group is the general "drivers" catch-all
# so they aren't discovered and run a second time.
#
# This spec catches drift between the two sides of that split: adding a
# new drivers/* subdirectory as its own group: entry (or removing one)
# without updating the matching exclusion/non-recursive branch in
# prepare_for_selftest_mfs would either silently double-run a subgroup's
# tests or (for a removed group) silently drop them from every case
# entirely. It extracts and executes the REAL prepare_for_selftest_mfs
# function body (not a hand-copied duplicate) against a synthetic
# directory tree built from the job yaml's own group list, so drift in
# either file is caught automatically without updating this spec by hand.
describe 'kselftests-bpf drivers group split' do
  let(:job_yaml_path) { "#{LKP_SRC}/jobs/kselftests/kselftests-bpf.yaml" }
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }

  def drivers_groups
    docs = YAML.load_stream(File.read(job_yaml_path))
    groups = docs.flat_map { |doc| doc.dig('kselftests-bpf', 'group') || [] }.uniq
    groups.select { |g| g == 'drivers' || g.start_with?('drivers/') }
  end

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  # Build a tools/testing/selftests/drivers/... layout for the given leaf
  # groups, each with a Makefile containing the '/lib.mk' marker the real
  # function greps for.
  def build_tree(root, leaves)
    leaves.each do |leaf|
      dir = File.join(root, leaf)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'Makefile'), "include ../../../lib.mk\n")
    end
  end

  def run_prepare(root, group)
    script = <<~BASH
      set -e
      cd #{root}
      die() { echo "DIE: $*" >&2; exit 1; }
      #{extract_function('prepare_for_selftest_mfs')}
      group=#{group}
      prepare_for_selftest_mfs
      echo "$selftest_mfs"
    BASH
    Bash.run(script).split("\n").reject(&:empty?).sort
  end

  it 'has a non-recursive exception for every drivers/* group with sub-groups also listed' do
    groups = drivers_groups
    script_src = File.read(script_path)

    groups.each do |g|
      next if g == 'drivers'

      children = groups.select { |o| o != g && o.start_with?("#{g}/") }
      next if children.empty?

      expect(script_src).to match(/"\$group"\s*=\s*"#{Regexp.escape(g)}"/),
                            "#{g} has its own sub-groups also listed (#{children.join(', ')}) " \
                            'but lib/tests/kselftests.sh has no non-recursive exception for it -- ' \
                            'a recursive `find` would rediscover and re-run those sub-groups a second time.'
    end
  end

  it 'excludes every split-out drivers/* group from the general drivers case, and keeps the rest' do
    split_out = drivers_groups.reject { |g| g == 'drivers' }
    # simulate a couple of "leftover" subgroups not split out, alongside
    # every subgroup that IS split out, so completeness/no-duplication can
    # be checked against the general "drivers" group's actual output.
    leftovers = %w[drivers/ntsync drivers/net/team drivers/dma-buf] - split_out

    Dir.mktmpdir do |root|
      build_tree(root, split_out + leftovers)

      general = run_prepare(root, 'drivers')

      split_out.each do |g|
        makefile = "#{g}/Makefile"
        expect(general).not_to include(makefile),
                               "general \"drivers\" case still discovers #{makefile}, which has its own " \
                               "job group: entry -- it will run twice. Add `-not -path '#{makefile}'` " \
                               "to prepare_for_selftest_mfs's general drivers branch."
      end

      leftovers.each do |g|
        makefile = "#{g}/Makefile"
        expect(general).to include(makefile),
                           "general \"drivers\" case no longer discovers #{makefile} -- check the " \
                           '-not -path exclusion list in prepare_for_selftest_mfs is not over-broad.'
      end
    end
  end

  it 'each split-out drivers/* group discovers exactly its own Makefile' do
    split_out = drivers_groups.reject { |g| g == 'drivers' }

    Dir.mktmpdir do |root|
      build_tree(root, split_out)

      split_out.each do |g|
        result = run_prepare(root, g)
        expect(result).to eq(["#{g}/Makefile"])
      end
    end
  end
end
