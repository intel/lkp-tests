#!/bin/sh

. $LKP_SRC/lib/reproduce-log.sh

#Clear resctrl and subsystem controllers mount point
clear_resctrl()
{
	resctrl_mounts=$(grep ' resctrl ' /proc/mounts)

	if [ -n "$resctrl_mounts" ]; then
		echo "$resctrl_mounts" |
			while read -r line; do
				resctrl_subsys=$(echo "$line" | awk '{ print $3 }')
				if [ "$resctrl_subsys" = "resctrl" ]; then
					resctrl_dir=$(echo "$line" | awk '{ print $2 }')
					log_cmd umount "$resctrl_dir"
					log_cmd rmdir "$resctrl_dir" 2>/dev/null
				fi
			done
	fi
}

#Create resctrl group
create_resctrl()
{
	local RESCTRL_MNT=$1
	local testcase=$2

	resctrl_mounts=$(grep ' resctrl ' /proc/mounts)

	#Only one resctrl filesystem is allowed to be mounted
	if [ -n "$resctrl_mounts" ]; then
		echo "$resctrl_mounts" |
			while read -r line; do
				resctrl_subsys=$(echo "$line" | awk '{ print $3 }')
				if [ "$resctrl_subsys" = "resctrl" ]; then
					return 0
				fi
			done
	fi

	log_cmd mkdir -p "$RESCTRL_MNT"
	log_cmd mount -t resctrl resctrl "$RESCTRL_MNT"
	log_cmd mkdir -p "$RESCTRL_MNT"/$testcase
}
