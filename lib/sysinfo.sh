#!/bin/sh

setup_threads_to_iterate()
{
	threads_to_iterate=1
	nr_node=$(echo /sys/devices/system/node/node* | wc -w)

	local threads_per_core
	local cores_per_node
	local cores_per_llc
	local nr_l3
	local nr_l2
	threads_per_core=$(lscpu | awk '/Thread\(s\) per core:/ { print $4 }')
	nr_l3=$(lscpu | grep 'L3' | awk -F '[()]' '{print $2}' | awk '{print $1}')
	nr_l2=$(lscpu | grep 'L2' | awk -F '[()]' '{print $2}' | awk '{print $1}')
	cores_per_llc=$((nr_l2 / nr_l3))
	cores_per_node=$((nr_cpu / nr_node / threads_per_core))

	# [    0.000000] Intel MultiProcessor Specification v1.4
	# [    0.000000]   mpc: 12-f012
	# [    0.000000] MPTABLE: bad signature [
	# [    0.000000] BIOS bug, MP table errors detected!...
	# [    0.000000] ... disabling SMP support. (tell your hw vendor)
	# [    0.000000] smpboot: Allowing 1 CPUs, 0 hotplug CPUs
	[ "$cores_per_node" = 0 ] && {
		echo "Invalid nr_cpu, nr_node or threads_per_core: $nr_cpu $nr_node $threads_per_core" >&2
		exit 1
	}

	local i
	for i in $(seq $nr_node)
	do
		threads_to_iterate="${threads_to_iterate} ${cores_per_llc} $((i * cores_per_node))"
	done

	[ "$nr_cpu" -ge 4 ] && {
		threads_to_iterate="${threads_to_iterate} $((nr_cpu * 3 / 4))"
		threads_to_iterate="${threads_to_iterate} $nr_cpu"
	}

	threads_to_iterate=$(echo $threads_to_iterate | tr ' ' '\n' | sort -un)
}

# caculate $cpu_utilization roughly without iowait time
calc_cpu_utilization()
{
	local sleep_secs=${1:-10}
	local cpu user_t nice_t system_t previdle_t idle_t rest

	read -r cpu user_t nice_t system_t previdle_t rest < /proc/stat
	local prevtotal_t=$((user_t+nice_t+system_t+previdle_t))

	sleep $sleep_secs

	read -r cpu user_t nice_t system_t idle_t rest < /proc/stat
	local total_t=$((user_t+nice_t+system_t+idle_t))

	if [ $prevtotal_t -eq $total_t ]; then
		cpu_utilization=0
	else
		cpu_utilization=$((100*((total_t-prevtotal_t)-(idle_t-previdle_t))/(total_t-prevtotal_t)))
	fi
}

