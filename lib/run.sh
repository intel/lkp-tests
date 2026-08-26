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
	for exec_path in $benchmark_path $benchmark_path/usr/local/bin $benchmark_path/bin; do
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

	while :; do
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

# Skip a need_x GUI benchmark cleanly when the only display adapter is a
# server BMC remote-management chip (e.g. ASPEED AST2xxx, PCI vendor
# 1a03) -- these have no monitor attached and Xorg's VT switch always
# fails: "(EE) xf86OpenConsole: Switching VT failed". Dies with a clear
# message instead of letting xinit start a doomed X session that only
# shows up later as a confusing "X connection ... broken" test failure.
check_need_x()
{
	[ "$need_x" = true ] || return 0

	local class_file vendor real_display=
	for class_file in "${PCI_DEVICES_DIR:-/sys/bus/pci/devices}"/*/class; do
		case "$(cat "$class_file" 2>/dev/null)" in
		0x03*) ;;
		*) continue ;;
		esac

		vendor=$(cat "${class_file%/class}/vendor" 2>/dev/null)
		case "$vendor" in
		0x1a03) ;; # ASPEED BMC remote-management graphics, no monitor
		*) real_display=1 ;;
		esac
	done

	[ -n "$real_display" ] ||
		die "no display adapter usable for X (only a BMC remote-management graphics chip is present, no monitor attached)"
}

# Print the override for this instance from a "<param>_by_instance"
# space-separated list, keyed by instance_id (1-based); prints nothing if
# the list is unset or has no entry at that position. Used by a
# cgroup2/nr_instances job to give sibling cgroups different demand for one
# parameter instead of every instance running an identical value:
#   instance_nr_threads_override=$(instance_override "$nr_threads_by_instance")
#   [[ -n "$instance_nr_threads_override" ]] && nr_threads=$instance_nr_threads_override
instance_override()
{
	local by_instance="$1"
	[ -n "$by_instance" ] || return

	local position=${instance_id:-1}
	set -- $by_instance
	eval "echo \${$position}"
}

# Print the "Instance: N" marker a cgroup2/nr_instances job's parse script
# tracks to attribute stats back to the sibling cgroup that produced them.
# instance_id is always exported by bin/run-test (defaults to 1 for a plain
# single-instance job), so this line is the same for every instance count.
echo_instance()
{
	echo "Instance: ${instance_id:-1}"
}
