#!/bin/sh

. $LKP_SRC/lib/env.sh

is_mount_point()
{
	if has_cmd mountpoint; then
		mountpoint -q $1
	else
		grep -q -F " $1 " /proc/mounts
	fi
}

check_mount()
{
	local dev=$1
	local mnt=$2

	[ "${dev#-}" = "$dev" ] || {
		echo "check_mount $*: please put options in the end" >&2
		return
	}

	is_mount_point $2 && return
	mkdir -p $2
	mount "$@" && return

	# debug mount failure
	local exit_code=$?
	echo "mount $*"
	mount
	cat /proc/filesystems
	return $exit_code
}

# NFSv4 is required for remote clients;
# NFSv3 looks more stable for local clients.
check_mount_nfs()
{
	check_mount "$@" -o v3 ||
	check_mount "$@"
}
