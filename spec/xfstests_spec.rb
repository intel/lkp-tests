require 'spec_helper'
require "#{LKP_SRC}/lib/bash"

describe 'xfstests' do
  describe 'is_test_in_group' do
    before(:all) do
      @benchmark_root = File.join(LKP_SRC, 'spec', 'benchmark_root')
    end

    def is_test_in_group(test, groups)
      groups = Array(groups).map { |group| "\"#{group}\"" }.join(' ')

      Bash.run <<EOF
        source #{LKP_SRC}/lib/tests/xfstests.sh

        export BENCHMARK_ROOT=#{@benchmark_root}

        is_test_in_group #{test} #{groups}

        echo $?
EOF
    end

    [
      { test: 'xfs-no-xfs-bug-on-assert', groups: 'xfs-no-xfs-bug-on-assert' },
      { test: 'xfs-115', groups: 'xfs-no-xfs-bug-on-assert' },

      { test: 'xfs-114', groups: 'xfs-scratch-reflink-scratch-rmapbt' },
      { test: 'xfs-307', groups: 'xfs-scratch-reflink-[0-9]*' },
      { test: 'xfs-scratch-reflink-00', groups: 'xfs-scratch-reflink-[0-9]*' },
      { test: 'generic-scratch-reflink-01', groups: %w(xfs-scratch-reflink-[0-9]* generic-scratch-reflink-[0-9]*) },
      { test: 'xfs-316', groups: %w(generic-scratch-reflink-[0-9]* xfs-scratch-reflink-[0-9]*) },

      { test: 'xfs-235', groups: 'xfs-scratch-rmapbt' },
      { test: 'generic-510', groups: 'generic-group-[0-9]*' },
      { test: 'generic-437', groups: 'generic-dax' },
      { test: 'generic-457', groups: 'generic-log-writes' },
      { test: 'generic-487', groups: 'generic-logdev' },
      { test: 'ext4-029', groups: 'ext4-logdev' },
      { test: 'xfs-275', groups: 'xfs-logdev' },

      { test: 'xfs-276', groups: 'xfs-realtime' },
      { test: 'xfs-realtime', groups: 'xfs-realtime.*' },
      { test: 'xfs-343', groups: 'xfs-realtime.*' },
      { test: 'xfs-realtime-scratch-rmapbt', groups: 'xfs-realtime.*' }
    ].each do |entry|
      it "#{entry[:test]} belongs to #{entry[:groups]}" do
        expect(is_test_in_group(entry[:test], entry[:groups])).to eq('0')
      end
    end

    [
      { test: 'generic-437', groups: 'generic-group-[0-9]*' },
      { test: 'ext4-group-00', groups: 'ext4-logdev' },
      { test: 'xfs-115', groups: 'generic-dax' },
      { test: 'xfs-437', groups: 'generic-dax' },
      { test: 'generic-510', groups: 'generic-dax' },
      { test: 'xfs-114', groups: 'xfs-scratch-reflink-[0-9]*' },
      { test: 'xfs-scratch-reflink', groups: 'xfs-scratch-reflink-scratch-rmapbt' }
    ].each do |entry|
      it "#{entry[:test]} not belongs to #{entry[:groups]}" do
        expect(is_test_in_group(entry[:test], entry[:groups])).to eq('1')
      end
    end
  end

  describe 'pattern_to_test' do
    [
      { fs: 'xfs', pattern: '_require_xfs_stress_online_repair$', test: 'xfs-stress-online-repair' },
      { fs: 'generic', pattern: 'holetest', test: 'generic-holetest' },
      { fs: 'xfs', pattern: '_require_no_xfs_bug_on_assert$', test: 'xfs-no-xfs-bug-on-assert' },
      { fs: 'xfs', pattern: '_require_scratch_reflink$ _require_xfs_scratch_rmapbt$', test: 'xfs-scratch-reflink-scratch-rmapbt' },
      { fs: 'generic', pattern: '_scratch_mkfs_blocksized', test: 'generic-scratch-mkfs-blocksized' },
      { fs: 'xfs', pattern: '_require_scratch_reflink$ holetest', test: 'xfs-scratch-reflink-holetest' },
      { fs: 'generic', pattern: 'holetest _require_xfs_stress_online_repair$', test: 'generic-holetest-xfs-stress-online-repair' }
    ].each do |entry|
      it "map #{entry[:fs]} #{entry[:pattern]}" do
        pkg_dir = LKP::Programs.find_pkg_dir(:xfstests)
        expect(Bash.run("source #{pkg_dir}/PKGBUILD; pattern_to_test \"#{entry[:fs]}\" \"#{entry[:pattern]}\"")).to eq(entry[:test])
      end
    end
  end
end
