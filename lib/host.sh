#!/bin/bash

# prefer $HOSTNAME over $(hostname)
get_hostname()
{
	[ -n "$HOSTNAME" ] && {
		echo "$HOSTNAME"
		return
	}

	hostname
}

set_tbox_group()
{
	local tbox=$1

	if [[ $tbox =~ ^(.*)-[0-9]+$ ]]; then
		tbox_group=$(echo ${BASH_REMATCH[1]} | sed -r 's#-[0-9]+-#-#')
	else
		tbox_group=$tbox
	fi
}

create_host_config()
{
	[ -n "$DRY_RUN" ] && return

	local host_name=$(get_hostname)
	local host_config="$LKP_SRC/hosts/${host_name}"
	[ -e $host_config ] || {
		echo "Creating testbox configuration file: $host_config."

		local mem_kb="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
		local mem_gb="$(((mem_kb) / 1024 / 1024))"
		local nr_cpu=$(nproc)

		cat <<EOT >>$host_config
nr_cpu: $nr_cpu
memory: ${mem_gb}G
hdd_partitions: ${hdd_partitions[*]}
ssd_partitions: ${ssd_partitions[*]}
local_run: 1
EOT
	}

	local tbox_group
	set_tbox_group $host_name

	local host_group_config="$LKP_SRC/hosts/${tbox_group}"
	[ -e $host_group_config ] || {
		echo "Creating testbox group configuration file: $host_group_config."
		cp $host_config $host_group_config
	}
}
