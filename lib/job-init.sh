#!/bin/sh

. $LKP_SRC/lib/upload.sh

mount_cgroup()
{
	[ -f "$CGROUP_MNT/tasks" ] && return

	[ -e '/proc/cgroups' ] || {
		echo "/proc/cgroups not found, skip cgroup mount."
		return 1
	}

	awk 'NR > 1 {print "\\s\\+" $1 "\\."}' /proc/cgroups >$TMP/availble-cgroup_subsys
	[ -f "$job" ] && cgroup_subsys=$(grep -o -f $TMP/availble-cgroup_subsys $job | sort | uniq)
	[ -n "$cgroup_subsys" ] || return
	cgroup_subsys=$(echo $cgroup_subsys | sed -e 's/\. / /g' -e 's/\.$/ /')
	log_cmd mkdir -p $CGROUP_MNT
	#Bind each subsystem to an individual hierachy
	for item in $cgroup_subsys; do
		log_cmd mkdir -p $CGROUP_MNT/$item
		log_cmd mount -t cgroup -o $item $item $CGROUP_MNT/$item
	done
}

validate_result_root()
{
	[ -n "$RESULT_ROOT" ] || RESULT_ROOT=$result_root
	[ -n "$RESULT_ROOT" ] || {
		echo 'No RESULT_ROOT' >&2
		run_job_failed=1
		return 1
	}

	return 0
}

supports_netfs()
{
	has_cmd mount.$1 || return
	grep -q -w $1 /proc/filesystems && return
	modprobe $1 >/dev/null || return
	grep -q -w $1 /proc/filesystems
}

supports_raw_upload()
{
	has_cmd lftp || has_cmd curl || has_cmd rsync
}

setup_result_service()
{
	[ -n "$result_service" ] && return
	[ -n "$NO_NETWORK" ] && return 1

	supports_raw_upload && result_service=raw_upload && return
	supports_netfs 'nfs' && result_service=$LKP_SERVER:/result && return
	supports_netfs 'cifs' && result_service=//$LKP_SERVER/result && return

	return 1
}

mount_result_root()
{
	echo "result_service: $result_service, RESULT_MNT: $RESULT_MNT, RESULT_ROOT: $RESULT_ROOT, TMP_RESULT_ROOT: $TMP_RESULT_ROOT"
	is_mount_point $RESULT_MNT && return 0

	case $result_service in
	tmpfs)
		result_fs=tmpfs
		mount -t tmpfs result $RESULT_MNT || return
		# result_service=tmpfs, RESULT_MNT=/10.239.97.5/result, RESULT_ROOT=/10.239.97.5/result/boot/1/lkp-hsw-d02/debian-x86_64-20180403.cgz/x86_64-rhel-7.6/gcc-7/1c163f4c7b3f621efff9b28a47abb36f7378d783/16
		mkdir -p $RESULT_ROOT
		;;
	raw_upload)
		# it means previous RESULT_ROOT is not a mount point, even
		# it may does not exist, but the later code will try to access $RESULT_ROOT.
		# To avoid the access problem, make it be same with TMP_RESLT_ROOT.
		export RESULT_ROOT=$TMP_RESULT_ROOT
		export result_fs=raw_upload # so that post-run can read it
		return
		;;
	*:*)
		local repeat=10
		result_fs=nfs
		for i in $(seq $repeat); do
			echo "mount.nfs: try $i time... mount.nfs -o vers=3 $result_service $RESULT_MNT"
			mount.nfs -o vers=3 $result_service $RESULT_MNT && return
			sleep 3
		done
		echo "mount nfs for $result_service failed"
		return 1
		;;
	//*/*)
		result_fs=cifs
		modprobe cifs 2>/dev/null
		local cifs_mount_option='-o guest'
		[ -n "$LKP_CIFS_PORT" ] && cifs_mount_option="$cifs_mount_option,port=$LKP_CIFS_PORT"
		mount.cifs $cifs_mount_option $result_service $RESULT_MNT || return
		;;
	9p/*)
		result_fs=virtfs
		mkdir -p "$RESULT_ROOT" && chmod 02775 "$RESULT_ROOT"
		export RESULT_MNT=$RESULT_ROOT
		export TMP_RESULT_ROOT=$RESULT_ROOT
		mkdir -p $TMP
		echo "mount -t 9p -o trans=virtio $result_service $RESULT_MNT -oversion=9p2000.L,posixacl,cache=loose"
		mount -t 9p -o trans=virtio $result_service $RESULT_MNT -oversion=9p2000.L,posixacl,cache=loose
		# for embedded rootfs(yocto) which cannot support 9p filesystem when use lkp-qemu
		[ $? -ne 0 ] && [ "$LKP_LOCAL_RUN" = "1" ] && return 0
		;;
	*)
		echo "unknown result_service $result_service" >&2
		return 1
		;;
	esac

	is_mount_point "$RESULT_MNT"
}

setup_result_root()
{
	validate_result_root || return 1

	export JOB_RESULT_ROOT=$RESULT_ROOT

	echo RESULT_ROOT=$RESULT_ROOT
	echo job=$job

	export TMP_RESULT_ROOT=$TMP/result
	mkdir -p $TMP_RESULT_ROOT

	setup_result_service || {
		export RESULT_ROOT=$TMP_RESULT_ROOT
		return
	}

	RESULT_PREFIX=/$LKP_SERVER
	export RESULT_PREFIX
	export RESULT_ROOT=$RESULT_PREFIX$RESULT_ROOT
	export RESULT_MNT=$RESULT_PREFIX/result

	mkdir -p $RESULT_MNT
	mount_result_root $RESULT_MNT || {
		if [ -z "$result_fs" ]; then
			set_job_state "unknown_result_service"
		elif grep -q -w "$result_fs" /proc/filesystems; then
			set_job_state 'error_mount'
			sleep 300
		else
			set_job_state "miss_$result_fs"
		fi
		return 1
	}

	# check emptiness except for files: dmesg pre-dmesg
	if [ "$result_fs" != "tmpfs" ]; then
		find "$RESULT_ROOT" -mindepth 1 ! -name '*dmesg*' | grep -q . &&
			echo "RESULT_ROOT not empty: $(ls -l "$RESULT_ROOT")" >&2
	fi

	return 0
}

# in case someone is logged in, give him at most 10hour time to do manual checks
wait_on_manual_check()
{
	# extra sleep for user login after a failed job,
	# if "wait_debug_on_fail" is defined in the job file
	[ "$run_job_failed" != 0 ] && [ -n "$wait_debug_on_fail" ] && {
		sleep $wait_debug_on_fail
	}

	for i in $(seq 600); do
		if [ -f $TMP/disturbed ]; then
			:
		elif ! has_cmd 'users'; then
			break
		else
			[ -n "$(users)" ] || break
		fi
		disturbed=1
		[ "$i" = 1 ] && set_job_state 'manual_check'
		sleep 60
	done
	return $disturbed
}

clean_job_resource()
{
	test -f /tmp/pid-tail || return
	kill "$(cat /tmp/pid-tail)"
	rm /tmp/pid-tail
}

job_done()
{
	$LKP_SRC/bin/event/wakeup job-finished
	touch $TMP/job-finished
	clean_job_resource
	wait_on_manual_check

	[ -n "$disturbed" ] && return

	# The randconfig VM boot/trinity tests often cannot reliably finish and
	# may not have the network to run trigger_post_process.
	# The host side monitor will upload qemu.time/dmesg/kmsg files and then
	# trigger_post_process for the test job in VM.
	[ -n "$nr_vm" ] && return

	trigger_post_process
}

refresh_lkp_tmp()
{
	export TMP=/tmp/lkp
	rm -fr $TMP
	mkdir -p $TMP
}

job_redirect_one()
{
	local file=$1
	shift

	tail -n 0 -f "$@" >$file &
	echo $! >>/tmp/pid-tail
}

job_redirect_stdout_stderr()
{
	[ -e /tmp/stdout ] || return
	[ -e /tmp/stderr ] || return

	job_redirect_one $TMP/stdout /tmp/stdout
	job_redirect_one $TMP/stderr /tmp/stderr
	job_redirect_one $TMP/output /tmp/stdout /tmp/stderr
}

job_env()
{
	if echo $job_file | grep -q '\.sh$'; then
		. $job_file
	else
		. ${job_file%.yaml}.sh
	fi

	export_top_env
}

# per-job initiation; should be invoked before run a job
job_init()
{
	refresh_lkp_tmp
	cp /proc/uptime $TMP/boot-time

	job_redirect_stdout_stderr

	job_env
}
