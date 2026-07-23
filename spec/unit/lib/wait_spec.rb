require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

describe 'check_oom' do
  def oom_detected?(dmesg_fixture)
    Dir.mktmpdir('wait-spec-') do |tmp|
      result = Bash.run(<<~SCRIPT)
        export TMP=#{tmp}
        dmesg() {
          cat <<'DMESG_FIXTURE'
        #{dmesg_fixture}
        DMESG_FIXTURE
        }
        source #{LKP_SRC}/lib/wait.sh
        check_oom
        [ -e "$TMP/OOM" ] && echo yes || echo no
      SCRIPT
      result == 'yes'
    end
  end

  it 'aborts the job on a system-wide OOM' do
    dmesg = <<~DMESG
      swapon01 invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
      Out of memory: Killed process 12345 (some-proc) total-vm:900000kB
    DMESG

    expect(oom_detected?(dmesg)).to be true
  end

  it 'does not abort the job on a kirk per-test memcg OOM (/ltp/test-<pid>)' do
    # kirk, LTP's test runner, places every test in its own memory cgroup;
    # a memcg kill scoped there only terminates that one test, which kirk
    # already records as failed and moves past.
    dmesg = <<~DMESG
      swapon01 invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
      memory: usage 1048576kB, limit 1048576kB, failcnt 49
      oom-kill:constraint=CONSTRAINT_MEMCG,oom_memcg=/ltp/test-10076,task_memcg=/ltp/test-10076,task=swapon01,pid=10184
      Memory cgroup out of memory: Killed process 10184 (swapon01) total-vm:1051484kB
    DMESG

    expect(oom_detected?(dmesg)).to be false
  end

  it 'aborts the job on a memcg OOM outside the kirk per-test cgroup convention' do
    dmesg = <<~DMESG
      some-proc invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
      oom-kill:constraint=CONSTRAINT_MEMCG,oom_memcg=/user.slice/some-other,task_memcg=/user.slice/some-other,task=some-proc,pid=999
      Memory cgroup out of memory: Killed process 999 (some-proc) total-vm:900000kB
    DMESG

    expect(oom_detected?(dmesg)).to be true
  end

  it 'aborts the job on a page allocation failure' do
    dmesg = 'some-proc: page allocation failure: order:5, mode:0x40cc0'

    expect(oom_detected?(dmesg)).to be true
  end

  it 'does nothing when dmesg has no OOM signature' do
    dmesg = '[    1.234567] Linux version 7.2.0-rc2'

    expect(oom_detected?(dmesg)).to be false
  end
end
