#!/bin/bash

. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/debug.sh

check_add_user()
{
	[ "x$1" != "x" ] || return
	grep -q -w "$1" /etc/passwd && return

	useradd -m "$1"
}

create_virtual_disk()
{
	dd if=/dev/zero of=raw.img bs=1M count=$1 || return
	local MIXED_BLOCK
	[ "$fs" = btrfs ] && MIXED_BLOCK="-M"
	mkfs.$fs $MIXED_BLOCK raw.img || return
	losetup /dev/loop0 raw.img || return
	has_virtual_disk=true
}

# check whether the machine is partitioned already
is_disc_partitioned()
{
	# eg. if not partition yet, $partitions=/dev/vdb /dev/vdc /dev/vdd
	# otherwise, $partitions=/dev/sda5 /dev/sda6 /dev/sda7 /dev/sda8
	sed_result=$(echo "$partitions" | sed -n '/[0-9]$/p')
	[ -n "$sed_result" ]
}

fs2_is_cifs()
{
	echo $fs2 | grep -q -e cifs -e smb
}

is_fs2_tests()
{
	[ -n "$fs2" ]
}

cifs_version()
{
	case $fs2 in
	cifs)
		echo "1.0"
		;;
	smbv2)
		echo "2.0"
		;;
	smbv3)
		echo "3.0"
		;;
	default)
		die "unknow version"
	esac
}

setup_cifs_config()
{
	local cifs_server_path=${cifs_server_paths%% *}
	local FS_TEST_DIR=${mount_points%% *}
	# get the mount path from local cifs server path: //localhost/fs/sdb1 => /fs/sdb1
	local LOCAL_MOUNT_PATH="/${cifs_server_path#//*/}"

	# mount the first partition for the local cifs server, where it's the cifs backend
	log_cmd mount ${partitions%% *} ${LOCAL_MOUNT_PATH}

	log_cmd mkdir -p /$fs2/$FS_TEST_DIR
	log_eval export FSTYP=cifs
	log_eval export TEST_DEV=$cifs_server_path
	log_eval export TEST_DIR=/$fs2/$FS_TEST_DIR

	# There's no separate scratch dev for CIFS, so we use the same server path
	# for SCRATCH_DEV and SCRATCH_MNT, similar to how TEST_DEV/TEST_DIR are set.
	# The xfstests suite will typically use a different subdirectory or share for scratch.
	log_eval export SCRATCH_DEV_POOL=$cifs_server_path
	log_eval export SCRATCH_MNT=/fs/scratch
	log_cmd mkdir -p $SCRATCH_MNT

	log_eval export CIFS_MOUNT_OPTIONS=\"-ousername=root,password=pass,noperm,vers=$(cifs_version),mfsymlinks,actimeo=0\"
}

setup_fs2_config()
{
	fs2_is_cifs || return 0

	setup_cifs_config
}

is_test_in_group()
{
	local test="$1"
	shift

	for group in "$@"; do
		_is_test_in_group "$test" "$group" && return
	done

	return 1
}

_is_test_in_group()
{
	# test: xfs-115 | ext4-group-00
	# group: xfs-no-xfs-bug-on-assert | ext4-logdev
	local test=$1
	local group=$2

	# Check for an exact match. This handles cases where:
	# 1. The 'test' is actually a full group name (e.g. test="generic-dax" matches group="generic-dax")
	# 2. The 'group' argument is a specific test name (e.g. test="generic-470" matches group="generic-470")
	[[ "$test" =~ ^$group$ ]] && return

	# test_prefix: xfs | ext4
	# test_number: 115 | group-00
	local test_prefix=${test%%-*}
	local test_number=${test#*-}

	# group_prefix: xfs | ext4
	local group_prefix=${group%%-*}

	[[ "$test_prefix" != "$group_prefix" ]] && return 1

	local group_files=$(find $BENCHMARK_ROOT/xfstests/tests/ -mindepth 1 -maxdepth 1 -type f -regex "^.+/$group$")
	[[ $group_files ]] || return

	grep -q -E "^$test_number$" $group_files
}

setup_partition_dev()
{
	local dev=${partitions#* }
	dev=${dev%% *}

	log_eval export "$1"="$dev"
}

setup_logwrites_dev()
{
	setup_partition_dev LOGWRITES_DEV
}

setup_scratch_logdev()
{
	setup_partition_dev SCRATCH_LOGDEV
}

setup_mkfs_options()
{
	local mkfs_options=""

	case "$fs" in
	f2fs)
		mkfs_options="-f"
		;;
	xfs)
		if is_test_in_group "$test" "xfs-projid16bit"; then
			mkfs_options="-mcrc=0"
		elif is_test_in_group "$test" "generic-dax"; then
			# new version of mkfs.xfs set reflink=1 as default and conflict with DAX mount
			# need to set reflink=0 manually
			mkfs_options="-mreflink=0"
		elif is_test_in_group "$test" "generic-group-[0-9]*" || { [[ "$nr_partitions" -ge 3 ]] && is_test_in_group "$test" "btrfs-log-writes" "generic-log-writes"; }; then
			mkfs_options="-mreflink=1"
		else
			# this doesn't apply to xfs-realtime-scratch-reflink
			#	reflink not supported with realtime devices
			is_test_in_group "$test" "xfs-scratch-reflink.*" "generic-scratch-reflink.*" && mkfs_options+="-mreflink=1 "

			is_test_in_group "$test" "xfs-scratch-rmapbt" "xfs-scratch-reflink-scratch-rmapbt" && mkfs_options+="-mrmapbt=1 "
		fi
		;;
	ext4)
		if is_test_in_group "generic-693" "$test"; then
			mkfs_options="-O encrypt"
		fi
		;;
	esac

	[[ $mkfs_options ]] || return 0

	local force_flag="-f"
	[[ "$fs" == "ext4" ]] && force_flag="-F"

	mkfs.$fs $force_flag $mkfs_options $TEST_DEV || die "mkfs.$fs $TEST_DEV failed"
	log_eval export MKFS_OPTIONS="\"$mkfs_options\""
}

setup_external_log_dev()
{
	local size=$1
	local dev_var=${2:-SCRATCH_LOGDEV}
	local target_dev

	if is_disc_partitioned; then
		create_virtual_disk "$size" || {
			echo "fail to create a virtual disk for log" 1>&2
			return 1
		}
		log_eval export "$dev_var"="/dev/loop0"
	else
		# If variable is already set (like SCRATCH_LOGDEV in calling scope), use it
		if [[ -n "${!dev_var}" ]]; then
			target_dev="${!dev_var}"
		elif [[ "$dev_var" == "SCRATCH_DEV" ]]; then
			target_dev=$SCRATCH_DEV
		else
			# Default to getting the 2nd partition (partitions format: "sda1 sda2 ...")
			target_dev=${partitions#* }
			target_dev=${target_dev%% *}
		fi

		local fdisk_size="+$size"
		[[ "$size" =~ ^[0-9]+$ ]] && fdisk_size="+${size}M"

		printf "n\np\n1\n\n%s\nw\n" "$fdisk_size" | fdisk "$target_dev"
		log_eval export "$dev_var"="${target_dev}1"
	fi
}

setup_logdev_config()
{
	if is_test_in_group "xfs-083" "$test" || is_test_in_group "xfs-275" "$test"; then
		# create a 100M partition for log, avoid
		# log size 67108864 blocks too large, maximum size is 1048576 blocks
		# if had partition already, create a virtual disk for log
		setup_external_log_dev 100
	elif is_test_in_group "$test" "ext4-logdev" "generic-logdev" "xfs-logdev"; then
		setup_external_log_dev 100
	elif is_test_in_group "$test" "generic-scratch-shutdown-metadata-journaling"; then
		# Filesystem must be larger than 300MB
		setup_external_log_dev 350
	elif is_test_in_group "generic-387" "$test"; then
		[[ -n "$SCRATCH_DEV_POOL" ]] && {
			SCRATCH_DEV=${SCRATCH_DEV_POOL##* }
			log_eval unset SCRATCH_DEV_POOL
		}
		setup_external_log_dev 1024 SCRATCH_DEV
	fi
}

setup_fs_config()
{
	log_eval export TEST_DIR=${mount_points%% *}
	log_eval export TEST_DEV=${partitions%% *}

	# f2fs needs this to prevent mount failure
	log_eval export FSTYP=$fs
	log_eval export SCRATCH_MNT=/fs/scratch

	log_cmd mkdir $SCRATCH_MNT -p

	# generic/339     udf_test not installed, please download and build the Philips
	# UDF Verification Software from http://www.extra.research.philips.com/udf/.
	# Then copy the udf_test binary to /lkp/benchmarks/xfstests/src/.
	# If you do not wish to run udf_test then set environment variable DISABLE_UDF_TEST
	# to 1.
	[[ "$fs" == "udf" ]] && log_eval export DISABLE_UDF_TEST=1

	if [[ "$fs" == "btrfs" ]] && [[ "$nr_partitions" -ge 4 ]]; then
		log_eval export SCRATCH_DEV_POOL=\"${partitions#* }\"
	else
		log_eval export SCRATCH_DEV=${partitions##* }
	fi

	## We could use the "pack-deps" job to generate the relevant dependency package with cgz format,
	## but sometimes the dependency package have a different layout with the original package.
	## For examle:
	## 1)the command "btrfs" under directory /sbin  in original rootfs.
	## 2)the command "btrfs" under directory /bin  in dependency packages.
	## this will result in the newer btrfs command can't override the original btrfs command,
	## moreover, /bin behind with /sbin directory in the default "PATH" environment.
	## so we need to adjust the "PATH" search order.
	export PATH="/bin/":$PATH

	if [[ "$fs" == "xfs" ]] && [[ "$nr_partitions" -ge 3 ]]; then
		setup_scratch_logdev
	fi

	[[ "${test%%-*}" == "xfs" ]] && {
		log_eval export SCRATCH_XFS_LIST_METADATA_FIELDS=u3.sfdir3.hdr.parent.i4
		log_eval export SCRATCH_XFS_LIST_FUZZ_VERBS=random
	}

	is_test_in_group "$test" "generic-no-xfs-bug-on-assert" "xfs-no-xfs-bug-on-assert" && {
		[[ -f /sys/fs/xfs/debug/bug_on_assert ]] && echo 0 > /sys/fs/xfs/debug/bug_on_assert
	}

	is_test_in_group "xfs-437" "$test" && {
		echo "LC_ALL=en_US.UTF-8" >> /etc/environment
		echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
		echo "LANG=en_US.UTF-8" > /etc/locale.conf
		locale-gen en_US.UTF-8
		log_eval export WORKAREA="$BENCHMARK_ROOT/xfstests/src/xfsprogs-dev"
	}

	# xfs-realtime xfs-realtime-scratch-rmapbt xfs-realtime-scratch-reflink
	is_test_in_group "$test" "xfs-realtime.*" && {
		log_eval export USE_EXTERNAL="yes"
		log_eval export SCRATCH_RTDEV="$SCRATCH_LOGDEV"
		log_eval unset SCRATCH_LOGDEV
	}

	setup_mkfs_options
	setup_logdev_config

	# need at least 3 partitions for TEST_DEV, SCRATCH_DEV and LOGWRITES_DEV
	if is_test_in_group "$test" "btrfs-log-writes" "generic-log-writes" && [[ "$nr_partitions" -ge 3 ]]; then
		setup_logwrites_dev

		[[ "$fs" == "btrfs" ]] && [[ -n "$SCRATCH_DEV_POOL" ]] && {
			log_eval export SCRATCH_DEV=${SCRATCH_DEV_POOL##* }
			log_eval unset SCRATCH_DEV_POOL
		}
	fi

	if is_test_in_group "generic-470" "$test"; then
		setup_logwrites_dev

		[[ "$fs" == "xfs" ]] && unset MKFS_OPTIONS
	fi

	if is_test_in_group "$test" "generic-dax" && [[ "$nr_partitions" -ge 3 ]]; then
		log_eval export MOUNT_OPTIONS=\"-o dax\"
	fi

	return 0
}

set_env()
{
	# "fsgqa" user is required in some of xfstests, thus check if such user
	# has already been added. If not, add "fsgqa" user.
	check_add_user "fsgqa"
	check_add_user "123456-fsgqa"
	check_add_user "fsgqa2"

	umount $mount_points

	# clear filesystem in partition
	for dev in ${partitions#* }
	do
		dd if=/dev/zero bs=512 count=512 of=$dev
	done

	if is_fs2_tests; then
		setup_fs2_config
	else
		setup_fs_config
	fi
}

run_cifs_tests()
{
	log_cmd ./check $exclude_file $all_tests
}

run_smbv2_tests()
{
	log_cmd ./check -E tests/cifs/exclude.incompatible-smb2.txt $exclude_file $all_tests
}

run_smbv3_tests()
{
	# generic/478 run over 1 hour in smbv3_test
	echo "generic/478" >> tests/cifs/exclude.very-slow.txt
	# generic/013 caused last_state: OOM
	echo "generic/013" >> tests/cifs/exclude.incompatible-smb3.txt
	log_cmd ./check -E tests/cifs/exclude.incompatible-smb3.txt $exclude_file $all_tests
}

run_fs_tests()
{
	[[ -s tests/exclude/$fs ]] && exclude_file="-E tests/exclude/$fs"
	log_cmd ./check $exclude_file $all_tests
}

run_fs2_tests()
{
	fs2_is_cifs && {
		exclude_file="$exclude_file -E tests/cifs/exclude.very-slow.txt"
		run_"$fs2"_tests
	}
}

run_test()
{
	## Currently, we support the following several format's test item.
	## Not-run, out-mismatch files are hard to maintain and do not use in the test, so remove them.
	## With "generic" testcase as an example:
	## - generic-all
	## - generic-127
	## - generic-quick/mid/slow1/slow2
	## - generic-new

	local test_dir="/$BENCHMARK_ROOT/xfstests/tests"

	local all_tests
	local all_tests_cmd

	if [[ "${test#*-}" == "all" ]]; then
		all_tests_cmd="cd tests && ls ${test%-*}/[0-9][0-9][0-9]"
	elif [[ "${test#*-}" == "new" ]]; then
		all_tests_cmd="cd tests && sed \"s:^:${test%-*}/:\" $test"
	elif [[ "${test%[a-z4]-[0-9][0-9][0-9]}" != "$test" ]]; then
		all_tests_cmd="echo ${test%-*}/${test#*-}"
	elif [[ "${test%-*}" == "$fs" ]]; then
		all_tests_cmd="sed \"s:^:${test%%-*}/:\" $test_dir/$test"
	elif [[ "${test#*-}" != "$test" ]]; then
		all_tests_cmd="sed \"s:^:${test%%-*}/:\" $test_dir/$test"
	else
		# Now rename $test-broken to $test-ignore wihch is easier to understand.
		all_tests_cmd="cd tests && ls $test/[0-9][0-9][0-9]"
	fi

	log_echo $all_tests_cmd
	all_tests=$(eval "$all_tests_cmd")

	[[ "${test#*-}" == "all" ]] || [[ -n "$all_tests" ]] || {
		echo "no test found"
		return 1
	}

	if is_fs2_tests; then
		run_fs2_tests
	else
		run_fs_tests
	fi

	return 0
}
