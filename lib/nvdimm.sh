# nvdimm functions

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
