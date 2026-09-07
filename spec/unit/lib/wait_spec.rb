require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

describe 'check_oom' do
  # bin/run-lkp and programs/oom-killer/monitor both act purely on
  # check_oom's own exit status (`check_oom && break`, `|| check_oom`) --
  # touching $TMP/OOM alone is not what callers key off of. Assert both
  # so a benign-OOM branch that matches its allowlist regex but still
  # returns success (e.g. a bare `return` after a successful `grep`,
  # which inherits the grep's own 0 exit code) is caught even though it
  # correctly leaves $TMP/OOM untouched.
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
        check_oom_status=$?
        oom_file=no
        [ -e "$TMP/OOM" ] && oom_file=yes
        echo "status=$check_oom_status file=$oom_file"
      SCRIPT
      status, file = result.scan(/status=(\d+) file=(\w+)/).first
      expect(file).to eq(status == '0' ? 'yes' : 'no')
      status == '0'
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
    # already records as failed and moves past. The kernel interleaves
    # nodemask=/cpuset=/mems_allowed= between constraint= and oom_memcg=
    # (see mm/oom_kill.c dump_oom_summary()) -- this fixture reproduces
    # that exact field order, unlike a hand-simplified line.
    dmesg = <<~DMESG
      swapon01 invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
      memory: usage 1048576kB, limit 1048576kB, failcnt 49
      oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=/,mems_allowed=0,oom_memcg=/ltp/test-10055,task_memcg=/ltp/test-10055,task=swapon01,pid=10166,uid=0
      Memory cgroup out of memory: Killed process 10166 (swapon01) total-vm:1051488kB
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

describe 'WAIT_POST_TEST_CMD/WAIT_JOB_FINISHED_CMD word-splitting' do
  # lib/wait.sh sets these to a two-word string ("<path>/wait post-test");
  # the wait_* wrappers below rely on the var staying UNQUOTED so the shell
  # re-splits it into [path, subcommand]. Quoting it collapses both words
  # into one nonexistent argv[0] and exec fails with "No such file or
  # directory" -- option_list_quoting_spec.rb statically guards this, but
  # this proves the real, current source still behaves correctly, rather
  # than trusting that static guard alone.
  #
  # $LKP_SRC/bin/event/wait itself is stubbed by pointing LKP_SRC at a temp
  # root (with the real lib/ symlinked in) so wait.sh's own hardcoded
  # "$LKP_SRC/bin/event/wait post-test" assignment resolves to our stub
  # instead of the real binary.
  def stub_wait_argv
    Dir.mktmpdir('wait-spec-') do |tmp|
      FileUtils.mkdir_p("#{tmp}/bin/event")
      File.write("#{tmp}/bin/event/wait", <<~STUB)
        #!/bin/sh
        printf '%s\\n' "$@" >#{tmp}/argv
      STUB
      FileUtils.chmod('+x', "#{tmp}/bin/event/wait")

      yield tmp

      File.exist?("#{tmp}/argv") ? File.read("#{tmp}/argv").lines(chomp: true) : nil
    end
  end

  it 'invokes wait_post_test with the path and subcommand as separate argv' do
    argv = stub_wait_argv do |tmp|
      Bash.run(<<~SCRIPT)
        export TMP=#{tmp}
        export LKP_SRC=#{tmp}
        source #{LKP_SRC}/lib/wait.sh
        wait_post_test --timeout 3
      SCRIPT
    end

    expect(argv).to eq(%w[post-test --timeout 3])
  end

  it 'invokes wait_timeout with the path and subcommand as separate argv' do
    argv = stub_wait_argv do |tmp|
      Bash.run(<<~SCRIPT)
        export TMP=#{tmp}
        export LKP_SRC=#{tmp}
        source #{LKP_SRC}/lib/wait.sh
        wait_timeout 5
      SCRIPT
    end

    expect(argv).to eq(%w[post-test --timeout 5])
  end

  it 'invokes wait_job_finished with the path and subcommand as separate argv' do
    argv = stub_wait_argv do |tmp|
      Bash.run(<<~SCRIPT)
        export TMP=#{tmp}
        export LKP_SRC=#{tmp}
        source #{LKP_SRC}/lib/wait.sh
        wait_job_finished --timeout 3
      SCRIPT
    end

    expect(argv).to eq(%w[job-finished --timeout 3])
  end
end
