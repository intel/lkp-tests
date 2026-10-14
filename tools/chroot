#!/bin/sh

if [ $# = 2 ]; then
	mount $1 $2 || exit
	shift
fi

mnt=$1

check_mount()
{
	mountpoint -q "$2" && return
	mount "$@"
}

check_mount /dev $mnt/dev --rbind
check_mount /sys $mnt/sys --bind
check_mount none $mnt/proc -t proc

chroot $mnt
