#!/bin/sh

WAIT_POST_TEST_CMD="$LKP_SRC/bin/event/wait post-test"
WAIT_JOB_FINISHED_CMD="$LKP_SRC/bin/event/wait job-finished"

wait_post_test()
{
	$WAIT_POST_TEST_CMD "$@"
}

wait_job_finished()
{
	$WAIT_JOB_FINISHED_CMD "$@"
}

wait_timeout()
{
	local timeout="${1:-1}"
	local exit_code

	# wait returns
	# - 0 on post-test => job finished, let's exit too
	# - 62 on timeout
	# - others on error => exit to avoid busy looping on caller side
	$WAIT_POST_TEST_CMD --timeout "$timeout"
	exit_code=$?
	[ $exit_code -eq 62 ] || exit $exit_code
}

setup_wait()
{
	echo $$ >>$TMP/.pid-wait-bg-procs
	echo ${0##*/} >>$TMP/.name-wait-bg-procs
}

explain_kill()
{
	local i
	for i; do
		echo -n "kill $i "
		cat /proc/$i/cmdline 2>/dev/null | tr '\0' ' '
		echo
	done
}

kill_one()
{
	explain_kill "$@"

	kill "$@" 2>/dev/null
	wait_post_test --timeout 3 && return
	kill -9 "$@" 2>/dev/null
}

kill_tests()
{
	if [ -z "$node_roles" ]; then
		local pid_tests="$(cat $TMP/pid-tests)"

		kill_one $pid_tests
	else
		if [ "${node_roles#*client}" != "${node_roles}" ]; then
			[ -f "$TMP/pid-tests" ] && {
				local pid_tests="$(cat $TMP/pid-tests)"
				kill_one $pid_tests
				wait_post_test --timeout 3 && return
			}

			local pid_run_tests="$(cat $TMP/pid-run-tests)"
			kill_one $pid_run_tests
		fi

		if [ "${node_roles#*server}" != "${node_roles}" ]; then
			# TODO: record each background daemon pid to pid-daemon
			[ -f "$TMP/pid-daemon" ] && {
				local pid_daemon="$(cat $TMP/pid-daemon)"
				kill_one $pid_daemon
				wait_post_test --timeout 3 && return
			}

			local pid_start_daemon="$(cat $TMP/pid-start-daemon)"
			kill_one $pid_start_daemon
		fi
	fi

	local pid_job="$(cat $TMP/run-job.pid)"
	wait_post_test --timeout 3 && return
	kill_one $pid_job
}

check_oom()
{
	local dmesg_out="$(dmesg)"

	echo "$dmesg_out" | grep -q -F \
		-e 'Out of memory' \
		-e 'invoked oom-killer: gfp_mask=0x' \
		-e ': page allocation failure: order:' || return

	# 'invoked oom-killer: gfp_mask=0x' is printed for both system-wide
	# and memcg-scoped OOM, but only a system-wide kill also prints
	# 'Out of memory' (mm/oom_kill.c prints "Memory cgroup out of
	# memory" for a memcg-scoped one instead). kirk, LTP's test runner,
	# places each test in its own per-test memory cgroup
	# (/ltp/test-<pid>); a memcg kill confined there only terminates
	# that one test, which kirk already records as failed and moves
	# past, so it must not abort the whole job.
	if ! echo "$dmesg_out" | grep -q -F -e 'Out of memory' -e ': page allocation failure: order:'; then
		echo "$dmesg_out" | grep -q -E 'oom-kill:constraint=CONSTRAINT_MEMCG,oom_memcg=/ltp/test-[0-9]+,' && return
	fi

	touch $TMP/OOM
}
