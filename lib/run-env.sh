#!/bin/sh

. $LKP_SRC/lib/host.sh

__local_run()
{
	host_name=$(get_hostname)
	host_file="$LKP_SRC/hosts/$host_name"
	if [ -f "$host_file" ] && grep -sq '^local_run:[[:space:]]*1' "$host_file"; then
		echo 1
	else
		echo 0
	fi
}

local_run()
{
	if ! [ "$LKP_LOCAL_RUN" = 1 ] && ! [ "$LKP_LOCAL_RUN" = 0 ]; then
		export LKP_LOCAL_RUN="$(__local_run)"
	fi
	[ "$LKP_LOCAL_RUN" = 1 ]
}

set_local_run()
{
	LKP_LOCAL_RUN=1
}
