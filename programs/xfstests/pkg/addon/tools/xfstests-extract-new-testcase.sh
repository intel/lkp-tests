#!/bin/bash

## This script is to extract testcase from xfstests/*-new result output file or generate generic group_file.
[[ -n "$LKP_SRC" ]] || LKP_SRC="$(dirname "$(dirname "$(readlink -e -v "$0")")")"

. "$LKP_SRC/lib/log.sh"
. "$LKP_SRC/lib/constant.sh"
. "$LKP_SRC/lib/install.sh"

usage()
{
	cat <<-EOF
Usage:
	$0 < fs xfstests-result >
	$0 generic group_number
Example:
	$0 xfs $RESULT_ROOT_DIR/xfstests/4HDD-ext4-ext4-new/snb-drag/debian-x86_64-2016-08-31.cgz/x86_64-rhel-7.2/gcc-6/4f7d029b9bf009fbee76bb10c0c4351a1870d2f3/0/output
	$0 generic 1
EOF
	exit 1
}

fs=$1
output=$2
([[ -n "$output" ]] && [[ -n "$fs" ]]) || usage
tmpfile=$(mktemp /tmp/xfstests-XXXXXX)

generate_averaged_group()
{
	local n=$1
	local number=$2
	for((i=0;i<"$n";i++))
	do
		awk -v n="$n" -v i="$i" '{if(NR%n == i) print $1}' data_completed > "$tmpfile"
		awk -v n="$n" -v i="$i" '{if(NR%n == i) print $1}' data_skip >> "$tmpfile"
		sort -u "$tmpfile" > "$fs-group$number"
		((number=number+1))
	done
}

generate_fs_group()
{
	# The xfstests result will output like below:
	# xfs/246	 2s
	# xfs/247	 [not run] Reflink not supported by scratch filesystem type: xfs
	#
	# The below pipeline is to:
	# 1. grep passed and skipped cases
	# 2. sort those passed cases by runtime
	# 3. sed to get only testcase name info
	grep "[0-9]s" "$output" | sort -k 2 -n | sed 's/'$fs'\///' | sed 's/s//' > data_completed
	grep "\[not run\]" "$output" | sort -k 1 | sed 's/'$fs'\///' > data_skip
	total_time=$(awk '{a+=$2} END {print a}' data_completed)
	# find max group_number, if not, return 0
	group_number=$(find "$(get_pkg_dir xfstests)/addon/tests" -name "$fs-group*" | grep -o "[0-9]*" | sort -n | tail -1)
	[[ -n "$group_number" ]] || group_number=0

	((group_number=group_number+1))

	# If total_time is over 10m, spilt them into averaged parts.
	# To make sure each group run similar time and within 10m.
	# Put skipped cases to each group in case they will pass in the future.
	if [[ "$total_time" -gt 600 ]]; then
		((n=total_time/600+1))
		generate_averaged_group "$n" "$group_number"
	else
		generate_averaged_group 1 "$group_number"
	fi
	rm data_completed data_skip
}

check_group_file()
{
	[[ -s "ext4-group$output" ]] && [[ -s "btrfs-group$output" ]] && [[ -s "xfs-group$output" ]] && return 0
	log_error "ext4/btrfs/xfs-group$output must all exist"
	return 1
}

# delete testcases which in the generic group from fs group.
delete_duplicated_testcases()
{
	local generic_group=$1
	local fs_group=$2
	grep -v -f "$generic_group" "$fs_group" > "$tmpfile"
	cp -v "$tmpfile" "$fs_group"
}

generate_generic_group()
{
	local group_number="$output"
	local generic_group="generic-group$group_number"
	check_group_file || return
	ext4_group="ext4-group$group_number"
	btrfs_group="btrfs-group$group_number"
	xfs_group="xfs-group$group_number"

	# The generic group includes cases which can pass with at least two fs.
	cat "$ext4_group" "$btrfs_group" "$btrfs_group" | sort | uniq | sort -u > "$generic_group"

	delete_duplicated_testcases "$generic_group" "$ext4_group"
	delete_duplicated_testcases "$generic_group" "$btrfs_group"
	delete_duplicated_testcases "$generic_group" "$xfs_group"
}

if [[ "$fs" == "generic" ]]; then
	generate_generic_group
else
	generate_fs_group
fi
rm "$tmpfile"
