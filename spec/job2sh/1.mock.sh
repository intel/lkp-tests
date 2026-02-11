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

	run_setup $LKP_SRC/setup/wrapper mysetup 'mock_arg'

	run_setup $LKP_SRC/setup/wrapper mysetup2

	run_test mode='thread' test='writeseek3' $LKP_SRC/tests/wrapper myprog

	start_daemon $LKP_SRC/daemon/wrapper mydaemon
}


extract_stats()
{
	export stats_part_begin=
	export stats_part_end=

	$LKP_SRC/stats/wrapper mysetup2
	env mode='thread' test='writeseek3' $LKP_SRC/stats/wrapper myprog

	$LKP_SRC/stats/wrapper time myprog.time
}


"$@"