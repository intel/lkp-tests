#!/bin/sh

. $LKP_SRC/lib/http.sh
. $LKP_SRC/lib/env.sh

get_net_devices()
{
	local net_devices
	local i
	for i in /sys/class/net/*/
	do
		[ "${i#*/lo/}" != "$i" ] && continue
		[ "${i#*/eth}" != "$i" ] && net_devices="$net_devices $(basename $i)"
		[ "${i#*/en}"  != "$i" ] && net_devices="$net_devices $(basename $i)"
	done

	echo "$net_devices"
}

net_devices_link()
{
	local operation=$1
	local net_devices
	net_devices=$(get_net_devices)
	local ndev
	for ndev in $net_devices
	do
		if has_cmd ip; then
			ip link set $ndev $operation
		elif has_cmd ifconfig; then
			ifconfig $ndev $operation
		fi
	done
}

network_ok()
{
	local i
	for i in /sys/class/net/*/
	do
		[ "${i#*/lo/}" != "$i" ] && continue
		[ "$(cat $i/operstate)" = 'up' ]		&& return 0
		[ "$(cat $i/carrier 2>/dev/null)" = '1' ]	&& return 0
	done

	return 1
}

network_up()
{
	net_devices_link up
	network_ok || { echo "LKP: waiting for network..."; sleep 10; }
	network_ok || sleep 20
	network_ok || sleep 30
	network_ok || return 1

	ip route | grep -q 'default via' || {
		# recover the default route
		[ -f /tmp/ip_route ] && ip route add "$(grep 'default via' /tmp/ip_route)"

		errno=$?
		[ $errno = 0 ] || {
			echo "failed to set default route"
			return $errno
		}
	}

	set_tbox_wtmp 'network_up'
}

network_down()
{
	set_tbox_wtmp 'network_down'
	# backup route table
	ip route > /tmp/ip_route
	net_devices_link down
}
