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

# A mount from a stalled network server can block in the kernel forever, which
# would burn the whole job time budget; bound it. SIGKILL is used because the
# blocked mount helper does not necessarily react to the default SIGTERM.
# MOUNT_TIMEOUT is in seconds.
mount_timeout()
{
	has_cmd timeout || {
		mount "$@"
		return
	}

	timeout -s KILL "${MOUNT_TIMEOUT:-120}" mount "$@"
}

# same as mount_timeout, for the mount.nfs helper used where the generic mount
# command may lack nfs support (e.g. a minimal busybox rootfs)
mount_nfs_timeout()
{
	has_cmd timeout || {
		mount.nfs "$@"
		return
	}

	timeout -s KILL "${MOUNT_TIMEOUT:-120}" mount.nfs "$@"
}

# "host:/path" style source, i.e. a network mount
is_network_mount_source()
{
	case $1 in
	*:/*) return 0 ;;
	esac

	return 1
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

	# only network mounts can hang on an unresponsive server; a local
	# filesystem mount may legitimately take long (e.g. log recovery)
	if is_network_mount_source "$dev"; then
		mount_timeout "$@" && return
	else
		mount "$@" && return
	fi

	# debug mount failure
	local exit_code=$?
	# 137: killed by SIGKILL, i.e. mount_timeout gave up on the server
	[ "$exit_code" -ne 137 ] || echo "mount $*: timed out after ${MOUNT_TIMEOUT:-120}s" >&2
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
