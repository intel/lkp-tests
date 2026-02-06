#!/bin/sh

. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/reproduce-log.sh

cd_benchmark()
{
	local benchmark_path="$(get_benchmark_path "$1")"

	log_cmd cd "$benchmark_path" || die "$benchmark_path does not exist"
}

get_benchmark_path()
{
	local suite=${1:-$suite}
	[ -n "$suite" ] || die "suite argument is empty"

	echo $BENCHMARK_ROOT/$suite
}

prepare_exec_path()
{
	local exec_name=${1:-$suite}
	local benchmark_path="$(get_benchmark_path)"

	local exec_path
	for exec_path in $benchmark_path $benchmark_path/usr/local/bin $benchmark_path/bin
	do
		[ -f "$exec_path/$exec_name" ] && {
			export PATH=$exec_path:$PATH
			echo "PATH=$PATH"
			return
		}
	done

	die "$exec_name is not found"
}

report_ops()
{
	stop_time=$(date +%s)
	echo "ops: $operations, ops/sec: $(echo "x = $operations / ($stop_time - $start_time); if (x < 1) print 0; x" | bc -l)"
	exit
}

test_loop()
{
	trap report_ops HUP

	start_time=$(date +%s)
	operations=0

	while :
	do
		do_test
		operations=$((operations + 1))
	done
}

runtime_loop()
{
	test_loop &
	local pid="$!"
	sleep $runtime
	kill -s HUP $pid
	wait
}
