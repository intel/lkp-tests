#!/bin/sh

# nvdimm functions

remove_dax_pmem_compat()
{
	local retries=${rmmod_retries:-10}

	for i in $(seq "$retries"); do
		log_cmd modprobe -r dax_pmem_compat && return
		sleep 10
	done
	return 1
}

wait_dax_initialization()
{
	local timeout=${wait_initialization_timeout:-30}

	for i in $(seq "$timeout"); do
		[ -f /sys/bus/dax/drivers/device_dax/unbind ] && return
		sleep 1
	done
	return 1
}

configure_namespace()
{
	ns=$1
	mode=$2

	bns=$(basename $ns)
	rmode=$(cat "$ns/mode")
	rsize=$(cat "$ns/size")
	echo "ns: $ns, mode: $mode, rmode: $rmode, rsize: $rsize"
	[ "$rsize" -eq 0 ] && return
	rmode=$(echo -n $rmode)
	[ "$rmode" = "$mode" ] && return
	ndctl create-namespace --reconfig=$bns \
					--force --mode="$mode" || exit 1
}

configure_nvdimm()
{
	for ns in /sys/bus/nd/devices/namespace*; do
		[ -e "$ns" ] || continue

		configure_namespace $ns $(echo -n $mode)
	done

	if [ -n "$ns_id" ]; then
		echo "ns_id: $ns_id"
		ns=/sys/bus/nd/devices/namespace$ns_id.0
		configure_namespace $ns $(echo -n $ns_mode)
	fi
}
