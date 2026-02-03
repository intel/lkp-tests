#!/bin/sh

. $LKP_SRC/lib/debug.sh

perf_event_paranoid="/proc/sys/kernel/perf_event_paranoid"

check_elements()
{
	local param=$1

	[ -n "$param" ] || die "parameter \"paranoid\" is empty"

	[ -e "$perf_event_paranoid" ] || die "can not find file $perf_event_paranoid"
	cat $perf_event_paranoid > /tmp/paranoid_old_value
}

setup_test_env()
{
	local param=$1

	case "$param" in
		not_paranoid_at_all)		paranoid_value=-1;;
		disallow_raw_tracepoint)	paranoid_value=0;;
		disallow_cpu_events)		paranoid_value=1;;
		disallow_kernel_profiling)	paranoid_value=2;;
	esac

	echo $paranoid_value > $perf_event_paranoid
	[ $paranoid_value = $(cat $perf_event_paranoid) ] || die "write value $paranoid_value to $perf_event_paranoid failed"

	# eaccess will fail if paranoid_value in [1,2], so run eacces under lkp
	[ $paranoid_value -gt 0 ] && sed -i -e 's/\$TESTS_DIR\/error_returns\/eacces/script -qc \"su lkp -c \\\"\$TESTS_DIR\/error_returns\/eacces\\\" | grep . --color=never\"/g' ./run_tests.sh

	# ./ioctl_10_query_bpf
	# Testing PERF_EVENT_IOC_SET_BPF ioctl.
	# Creating a kprobe tracepoint event
	# Cannot open /sys/kernel/tracing/kprobe_events!
	# You may want to: mount -t tracefs nodev /sys/kernel/tracing
	# Testing PERF_EVENT_IOC_QUERY_BPF ioctl...
	mount -t tracefs nodev /sys/kernel/tracing
}

clean_test_env()
{
	if [ -e "/tmp/paranoid_old_value" ]; then
		local orig_value=$(cat /tmp/paranoid_old_value)
		echo $orig_value > $perf_event_paranoid
		[ $orig_value = $(cat $perf_event_paranoid) ] || echo "Warning: write value $orig_value to $perf_event_paranoid failed"
		rm -f /tmp/paranoid_old_value
	fi
}
