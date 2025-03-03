#!/bin/bash

LKP_DOCKER_HOSTNAME="lkp-docker"
LKP_DOCKER_TEST_DIR="/home/$USER/lkp"

exec_cmd()
{
	echo "$@"
	"$@"
}

load_container()
{
	local container="$1"
	shift

	[[ "$container" ]] || {
		echo "Container file is not specified."
		return 1
	}

	[[ "$container" == /* ]] || container=$LKP_DOCKER_TEST_DIR/containers/$container

	[[ -f "$container" ]] || {
		echo "Container file does not exist at $container."
		return 1
	}

	local key value

	while IFS='=' read -r key value; do
		# trim any leading or trailing whitespace
		key=$(echo $key | xargs)
		value=$(echo $value | xargs)

		[[ $value ]] && eval "opt_$key=$value"
	done < $container

	return 0
}
