#!/bin/sh

export_top_env()
{
	export suite='mock-suite'
	export testcase='mock-testcase'
	export category='mock-category'
	export job_origin='spec/job2sh/1.mock.yaml'

	[ -n "$LKP_SRC" ] ||
	export LKP_SRC=/lkp/${user:-lkp}/src
}


run_job()
{
	echo $$ > $TMP/run-job.pid

	. $LKP_SRC/lib/http.sh
	. $LKP_SRC/lib/job.sh
	. $LKP_SRC/lib/env.sh

	export_top_env

	run_setup $LKP_SRC/bin/run-setup mysetup 'mock_arg'

	run_setup $LKP_SRC/bin/run-setup mysetup2

	run_monitor $LKP_SRC/bin/run-monitor mymonitor
	run_monitor $LKP_SRC/bin/run-no-stdout-monitor mymonitor2
	run_monitor $LKP_SRC/bin/run-one-shot-monitor mymonitor3

	run_test mode='thread' test='writeseek3' $LKP_SRC/bin/run-test myprog

	start_daemon $LKP_SRC/bin/run-daemon mydaemon
}


extract_stats()
{
	export stats_part_begin=
	export stats_part_end=

	$LKP_SRC/bin/run-stats mysetup2
	env mode='thread' test='writeseek3' $LKP_SRC/bin/run-stats myprog
	$LKP_SRC/bin/run-stats mymonitor
	$LKP_SRC/bin/run-stats mymonitor2
	$LKP_SRC/bin/run-stats mymonitor3

	$LKP_SRC/bin/run-stats time myprog.time
}


"$@"