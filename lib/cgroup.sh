#!/bin/sh

. $LKP_SRC/lib/reproduce-log.sh

#Clear cgroups and subsystem controllers mount point for v1 version
clear_cgroup()
{
	cgmounts=$(grep ' cgroup ' /proc/mounts)

	if [ -n "$cgmounts" ]; then
		echo "$cgmounts" |
		while read -r line
		do
			subsys=$(echo $line | awk '{ print $1 }')
			subsys_mount=$(echo $line | awk '{ print $2 }')
			if [ $(basename $subsys_mount) = "systemd" ]; then
				continue
			fi
			cgroups=$(find $subsys_mount -type d | tail -n +2 | tac)
			for cgroup in $cgroups
			do
				rmdir $cgroup 2>/dev/null
			done
			umount $subsys_mount
		done
	fi
}

#clear cgroups and subsystem controllers mount point for v2 version
clear_cgroup2()
{
	cgroup2_mount=$(grep ' cgroup2 ' /proc/mounts | awk '{ print $2 }')

	if [ -n "$cgroup2_mount" ]; then
		cgroups2=$(find $cgroup2_mount -type d | tail -n +2 | tac)
		for cgroup2 in $cgroups2
		do
			rmdir $cgroup2 2>&1
		done
		umount $cgroup2_mount 2>&1
	fi
}

#Bind each subsystem to an individual hierachy and create an individual control group
create_cgroup()
{
	local CGROUP_MNT=$1
	local testcase=$2

	subsys=$(awk 'NR > 1 {printf $1 " "}' /proc/cgroups)

	for item in $subsys
	do
		if [ "$item" = "cpu" -o "$item" = "cpuacct" ] &&
			   ! mountpoint -q "$CGROUP_MNT/cpu,cpuacct"; then
			log_cmd mkdir -p $CGROUP_MNT/cpu,cpuacct 2>/dev/null
			log_cmd mount -t cgroup -o cpu,cpuacct cpu,cpuacct $CGROUP_MNT/cpu,cpuacct 2>/dev/null
			log_cmd mkdir -p $CGROUP_MNT/cpu,cpuacct/$testcase
			continue
		fi
		if ! mountpoint -q "$CGROUP_MNT/$item"; then
			log_cmd mkdir -p $CGROUP_MNT/$item
			log_cmd mount -t cgroup -o $item $item $CGROUP_MNT/$item
		fi
		log_cmd mkdir -p $CGROUP_MNT/$item/$testcase
	done
}

init_cgroup2()
{
	local CGROUP2_MNT=$1

	log_cmd mkdir -p $CGROUP2_MNT
	log_cmd mount -t cgroup2 none $CGROUP2_MNT
	sub_controllers=$(cat $CGROUP2_MNT/cgroup.controllers)

	for controller in $sub_controllers; do
		log_eval "echo '+$controller' > '$CGROUP2_MNT/cgroup.subtree_control'"
	done
}

#Bind all the subsystem controllrs to an unified hierachy and create a control group
create_one_cgroup2()
{
	local CGROUP2_MNT=$1
	local testcase=$2

	log_cmd mkdir -p $CGROUP2_MNT/$testcase
}

#According to
#https://github.com/torvalds/linux/blob/master/Documentation
#/cgroup-v1/cgroups.txt, to remove a task from its current
#cgroup you must move it into a new cgroup (possibly the
#root cgroup) by writing to the new cgroup's tasks file.
#Thus we leverage this idea to reset the cpuset of current
#task by moving current task to the root dir of each cgroup.cpuset,
#so that current task(and its descendant) are allowed to migrate
#among all online CPUs.
reset_current_cpuset()
{
	cgmounts=$(grep ' cgroup ' /proc/mounts)

	if [ -n "$cgmounts" ]; then
		echo "$cgmounts" |
		while read -r line
		do
			subsys_mount=$(echo $line | awk '{ print $1 }')
			# find the cpuset subsystem
			# grep ' cgroup ' /proc/mounts |  awk '{ print $1 }'
			# cgroup
			# cpuset
			# cpu,cpuacct
			# blkio
			# memory
			# devices
			# freezer
			# net_cls
			# perf_event
			# net_prio
			# hugetlb
			# pids
			# rdma
			if [ $subsys_mount = "cpuset" ]; then
				subsys_mount_dir=$(echo $line | awk '{ print $2 }')
				echo $$ > $subsys_mount_dir/tasks
			fi
		done
	fi
}
