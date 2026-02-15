#!/bin/sh

export_top_env()
{
	export suite='hackbench'
	export testcase='hackbench'
	export category='benchmark'
	export nr_threads=18
	export iterations=8
	export job_origin='jobs/hackbench.yaml'
	export testbox='lkp-docker'
	export arch='x86_64'
	export tbox_group='lkp-docker'
	export nr_cpu=36
	export memory='62G'
	export hdd_partitions=
	export ssd_partitions=
	export local_run=1

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

	run_monitor $LKP_SRC/bin/run-monitor kmsg
	run_monitor $LKP_SRC/bin/run-no-stdout-monitor boot-time
	run_monitor $LKP_SRC/bin/run-monitor uptime
	run_monitor $LKP_SRC/bin/run-monitor iostat
	run_monitor $LKP_SRC/bin/run-monitor heartbeat
	run_monitor $LKP_SRC/bin/run-monitor vmstat
	run_monitor $LKP_SRC/bin/run-monitor numa-numastat
	run_monitor $LKP_SRC/bin/run-monitor numa-vmstat
	run_monitor $LKP_SRC/bin/run-monitor numa-meminfo
	run_monitor $LKP_SRC/bin/run-monitor proc-vmstat
	run_monitor $LKP_SRC/bin/run-monitor proc-stat
	run_monitor $LKP_SRC/bin/run-monitor meminfo
	run_monitor $LKP_SRC/bin/run-monitor slabinfo
	run_monitor $LKP_SRC/bin/run-monitor interrupts
	run_monitor $LKP_SRC/bin/run-monitor lock_stat
	run_monitor lite_mode=1 $LKP_SRC/bin/run-monitor perf-sched
	run_monitor $LKP_SRC/bin/run-monitor softirqs
	run_monitor $LKP_SRC/bin/run-one-shot-monitor bdi_dev_mapping
	run_monitor $LKP_SRC/bin/run-monitor diskstats
	run_monitor $LKP_SRC/bin/run-monitor nfsstat
	run_monitor $LKP_SRC/bin/run-monitor cpuidle
	run_monitor $LKP_SRC/bin/run-monitor cpufreq-stats
	run_monitor $LKP_SRC/bin/run-monitor turbostat
	run_monitor $LKP_SRC/bin/run-monitor sched_debug
	run_monitor $LKP_SRC/bin/run-monitor perf-stat
	run_monitor $LKP_SRC/bin/run-monitor mpstat
	run_monitor debug_mode=0 $LKP_SRC/bin/run-no-stdout-monitor perf-profile

	run_test mode='threads' ipc='pipe' $LKP_SRC/bin/run-test hackbench
}


extract_stats()
{
	export stats_part_begin=
	export stats_part_end=

	env mode='threads' ipc='pipe' $LKP_SRC/bin/run-stats hackbench
	$LKP_SRC/bin/run-stats kmsg
	$LKP_SRC/bin/run-stats boot-time
	$LKP_SRC/bin/run-stats uptime
	$LKP_SRC/bin/run-stats iostat
	$LKP_SRC/bin/run-stats vmstat
	$LKP_SRC/bin/run-stats numa-numastat
	$LKP_SRC/bin/run-stats numa-vmstat
	$LKP_SRC/bin/run-stats numa-meminfo
	$LKP_SRC/bin/run-stats proc-vmstat
	$LKP_SRC/bin/run-stats meminfo
	$LKP_SRC/bin/run-stats slabinfo
	$LKP_SRC/bin/run-stats interrupts
	$LKP_SRC/bin/run-stats lock_stat
	env lite_mode=1 $LKP_SRC/bin/run-stats perf-sched
	$LKP_SRC/bin/run-stats softirqs
	$LKP_SRC/bin/run-stats diskstats
	$LKP_SRC/bin/run-stats nfsstat
	$LKP_SRC/bin/run-stats cpuidle
	$LKP_SRC/bin/run-stats cpufreq-stats
	$LKP_SRC/bin/run-stats turbostat
	$LKP_SRC/bin/run-stats sched_debug
	$LKP_SRC/bin/run-stats perf-stat
	$LKP_SRC/bin/run-stats mpstat
	env debug_mode=0 $LKP_SRC/bin/run-stats perf-profile

	$LKP_SRC/bin/run-stats time hackbench.time
	$LKP_SRC/bin/run-stats dmesg
	$LKP_SRC/bin/run-stats kmsg
	$LKP_SRC/bin/run-stats last_state
	$LKP_SRC/bin/run-stats stderr
	$LKP_SRC/bin/run-stats time
}


"$@"