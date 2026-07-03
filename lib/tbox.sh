#!/bin/sh

tbox_cant_kexec()
{
	is_virt && return 0

	has_cmd kexec || return 0
	has_cmd cpio || return 0

	return 1
}

__next_job()
{
	NEXT_JOB="/tmp/next-job-$LKP_USER"

	echo "getting new job..."
	local mac="$(show_mac_addr)"
	local last_kernel=
	[ -n "$job" ] && last_kernel="last_kernel=$(escape_cgi_param $(grep ^kernel: $job | cut -d \" -f 2))&"
	http_get_cgi "cgi-bin/gpxelinux.cgi?hostname=${HOSTNAME}&mac=$mac&${last_kernel}${manual_reboot}lkp_wtmp" \
		$NEXT_JOB || {
		echo "cannot get next job" 1>&2
		set_tbox_wtmp 'cannot_get_next_job'
		return 1
	}

	grep -q "^KERNEL " $NEXT_JOB || {
		echo "no KERNEL found" 1>&2
		set_tbox_wtmp 'no_kernel_found'
		cat $NEXT_JOB
		return 1
	}

	return 0
}
