require 'spec_helper'
require "#{LKP_SRC}/lib/stats"

describe StatClassifier do
  describe '.function_stat?' do
    it 'treats a matched failure pattern as a function stat' do
      expect(described_class.function_stat?('dmesg.INFO:task_blocked_for_more_than#seconds')).to be true
      expect(described_class.function_stat?('xfstests.btrfs.192.fail')).to be true
    end

    it 'treats a matched skip pattern as a function stat' do
      expect(described_class.function_stat?('kselftests.net.foo.skip')).to be true
    end

    it 'does not treat an unmatched stat as a function stat' do
      expect(described_class.function_stat?('perf-profile.calltrace.cycles-pp.error_entry')).to be false
    end

    it 'excludes .time./.timestamp:/.bootstage: stats before checking patterns' do
      expect(described_class.function_stat?('foo.time.bar')).to be false
      expect(described_class.function_stat?('foo.timestamp:bar')).to be false
      expect(described_class.function_stat?('foo.bootstage:bar')).to be false
    end
  end

  describe '.latency_stat?' do
    it 'matches an etc/index-latency-all.yaml key' do
      expect(described_class.latency_stat?('dd.kill_time')).to be true
    end

    it 'does not match a stat outside that index' do
      expect(described_class.latency_stat?('some.random.stat')).to be false
    end
  end

  describe '.failure_stat?' do
    it 'matches etc/stat-classifier.yml fail rules' do
      expect(described_class.failure_stat?('dmesg.INFO:task_blocked_for_more_than#seconds')).to be true
      expect(described_class.failure_stat?('perf-profile.calltrace.cycles-pp.error_entry')).to be false
    end

    it 'matches a real locktorture/rcutorture hotplug stat' do
      expect(described_class.failure_stat?('locktorture.spin_lock.lock_hotplug')).to be true
      expect(described_class.failure_stat?('rcutorture.rcu_pathological.rcu_hotplug')).to be true
    end
  end

  describe '.pass_stat?' do
    it 'matches a pass rule' do
      expect(described_class.pass_stat?('xfstests.generic.001.pass')).to be true
      expect(described_class.pass_stat?('xfstests.generic.001.fail')).to be false
    end
  end

  describe 'a stat matched by more than one type' do
    it 'is reported by exactly one of failure_stat?/pass_stat?/skip_stat?' do
      # kmsg.* is a blanket fail, but a kernel self-test that passed is a pass
      stat = 'kmsg.test_printf.pass'

      expect([described_class.failure_stat?(stat), described_class.pass_stat?(stat), described_class.skip_stat?(stat)]).to eq([false, true, false])
    end
  end

  describe 'rules that exist only in etc/stat-classifier.yml' do
    it 'treats nvml test_skip and xfstests expunged as skips, hence function stats' do
      expect(described_class.skip_stat?('nvml.blk_rw_TEST12.test_skip')).to be true
      expect(described_class.skip_stat?('xfstests.generic.235.expunged')).to be true
      expect(described_class.function_stat?('nvml.blk_rw_TEST12.test_skip')).to be true
    end

    it 'treats kselftests xfail and leaking-addresses dmesg stats as failures' do
      expect(described_class.failure_stat?('kselftests.net.foo.xfail')).to be true
      expect(described_class.failure_stat?('leaking-addresses.dmesg.mappedAPICto_fee00000')).to be true
    end
  end

  describe 'a stat with many dot-separated segments' do
    # A kmemleak backtrace becomes a stat name with dozens of segments; the
    # rule regexps must match (or reject) it in linear-ish time instead of
    # backtracking exponentially over the segment boundaries.
    let(:call_chain) { (1..22).map { |i| "frame#{i}" }.join('.') }

    def elapsed
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end

    it 'classifies a long kmemleak stat as a failure quickly' do
      stat = "kmemleak.softirq.unreferenced_object.#{call_chain}"

      expect(elapsed { expect(described_class.failure_stat?(stat)).to be true }).to be < 0.5
    end

    it 'rejects a long stat no rule matches quickly' do
      stat = "perf-profile.calltrace.#{call_chain}"

      expect(elapsed { expect(described_class.function_stat?(stat)).to be false }).to be < 0.5
    end
  end

  describe '.skip_stat?' do
    it 'matches a skip rule' do
      expect(described_class.skip_stat?('kselftests.net.foo.skip')).to be true
      expect(described_class.skip_stat?('kselftests.net.foo.not_installed')).to be true
      expect(described_class.skip_stat?('kselftests.net.foo.job_skip')).to be true
      expect(described_class.skip_stat?('kselftests.net.foo.block')).to be true
    end

    it 'does not match a pass/fail-suffixed stat' do
      expect(described_class.skip_stat?('xfstests.generic.001.pass')).to be false
      expect(described_class.skip_stat?('xfstests.generic.001.fail')).to be false
    end
  end

  describe '.memory_stat?' do
    it 'matches an etc/memory-stat-prefixes prefix' do
      expect(described_class.memory_stat?('meminfo.MemFree')).to be true
    end

    it 'does not match a monitor outside that prefix list' do
      expect(described_class.memory_stat?('vmstat.something')).to be false
    end
  end

  describe '.bisectable_stat?' do
    it 'allows a stat matched by the allowlist even if also denylisted' do
      expect(described_class.bisectable_stat?('stderr.umount:/tmp/vm-scalability-tmp:target_is_busy')).to be true
    end

    it 'denies a stat matched only by the denylist' do
      expect(described_class.bisectable_stat?('ebizzy.throughput.per_thread.stddev_percent')).to be false
    end

    it 'allows a stat matched by neither list' do
      expect(described_class.bisectable_stat?('some.random.stat')).to be true
    end

    # test suites that inject memory errors through the EDAC debugfs
    # interface on purpose trigger these reports; the suite's own
    # pass/fail result is what should drive a bisect, not the report
    %w[dmesg.EDAC_MC7:#CE dmesg.EDAC_MC11:#UE dmesg.EDAC_MC0:#CE_row_#,_chan_#_on_mc#0csrow#2channel#1].each do |stat|
      it "denies the EDAC memory error stat #{stat}" do
        expect(described_class.bisectable_stat?(stat)).to be false
      end
    end
  end

  describe '.kpi_stat?' do
    it 'excludes stats on the hardcoded KPI_STAT_DENYLIST' do
      expect(described_class.kpi_stat?('vm-scalability.stddev', nil)).to be false
      expect(described_class.kpi_stat?('unixbench.incomplete_result', nil)).to be false
    end

    it 'accepts a stat whose base is a known test' do
      expect(described_class.kpi_stat?('vm-scalability.throughput', nil)).to be true
    end

    it "excludes a known test's time. stats" do
      expect(described_class.kpi_stat?('vm-scalability.time.elapsed', nil)).to be false
    end

    it "rejects a stat whose base isn't a known test" do
      expect(described_class.kpi_stat?('nonexistent-test.throughput', nil)).to be false
    end
  end

  describe 'instance API built from definitions' do
    before(:all) do
      @classifier = described_class.new('pass' => { '*' => 'pass' }, 'fail' => { '*' => 'fail', 't' => 'crash crashed' },
                                        'skip' => { '*' => 'skip block' }, 'skipped' => { '*' => 'skipped' })
    end

    describe '.initialize' do
      it 'defines singleton methods' do
        expect(@classifier).to respond_to(:pass?)
        expect(@classifier).to respond_to(:skipped?)

        expect(described_class.new({})).not_to respond_to(:pass?)
      end
    end

    describe '.pass?' do
      context 'when given passed stat' do
        it 'returns true' do
          expect(@classifier).to be_pass('s.x.pass')
          expect(@classifier).to be_pass('s.x.y.pass')
          expect(@classifier).to be_pass('t.x.pass')
          expect(@classifier).to be_pass('t.x.PaSS')
          expect(@classifier).to be_pass('t.pass')
        end
      end

      context 'when given non passed stat' do
        it 'returns false' do
          expect(@classifier).not_to be_pass('s.x.passed')
          expect(@classifier).not_to be_pass('t.x.failed')
          expect(@classifier).not_to be_pass('....pass')
        end
      end
    end

    describe '.fail?' do
      context 'when given failed stat' do
        it 'returns true' do
          expect(@classifier).to be_fail('s.x.fail')
          expect(@classifier).to be_fail('t.x.crash')
        end
      end

      context 'when given non failed stat' do
        it 'returns false' do
          expect(@classifier).not_to be_fail('s.x.failed')
          expect(@classifier).not_to be_fail('s.x.crash')
        end
      end
    end

    describe '.skip?' do
      context 'when given skipped stat' do
        it 'returns true' do
          expect(@classifier).to be_skip('s.x.block')
        end
      end

      context 'when given non skipped stat' do
        it 'returns false' do
          expect(@classifier).not_to be_skip('s.block.failed')
          expect(@classifier).not_to be_skip('s.x.skipped')
        end
      end
    end

    describe '.result?' do
      context 'when given a valid stat' do
        it 'returns true' do
          expect(@classifier).to be_result('s.x.BLOCK')
          expect(@classifier).to be_result('s.x.y.z.pass')
          expect(@classifier).to be_result('s.x_y-z.skipped')
        end
      end

      context 'when given an invalid stat' do
        it 'returns false' do
          expect(@classifier).not_to be_result('s.block.error')
          expect(@classifier).not_to be_result('....pass')
        end
      end
    end

    describe '.type against the real etc/stat-classifier.yml' do
      before(:all) do
        @real_classifier = described_class.new
      end

      it 'classifies a real locktorture/rcutorture hotplug stat as fail' do
        expect(@real_classifier.type('locktorture.spin_lock.lock_hotplug')).to eq('fail')
        expect(@real_classifier.type('rcutorture.rcu_pathological.rcu_hotplug')).to eq('fail')
      end

      it "prefers a testcase's own pass pattern over fail's blanket catch-all for the same prefix" do
        # dmesg/last_state both have a specific `pass:` word AND a blanket
        # `fail: .+` entry; pass must win, since type() checks types in the
        # order they appear in the yml (pass before fail) -- do not reorder
        # the top-level pass/fail/skip keys in the yml without updating this.
        expect(@real_classifier.type('dmesg.boot_succeeded')).to eq('pass')
        expect(@real_classifier.type('last_state.completed')).to eq('pass')
      end

      it "classifies a '.warn'-suffixed stat as fail for any testcase, not just avocado" do
        expect(@real_classifier.type('some-testcase.foo.warn')).to eq('fail')
      end

      it 'classifies a captured stderr line as fail' do
        expect(@real_classifier.type('stderr.umount:/tmp/vm-scalability-tmp:target_is_busy')).to eq('fail')
      end
    end
  end
end
