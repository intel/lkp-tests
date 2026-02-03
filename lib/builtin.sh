#!/bin/bash

if [ -n "$BASH_VERSION" ]; then

sleep()
{
	local seconds=${1%s}
	[[ $seconds == *"m"* ]] && seconds=$(( ${seconds%m} * 60 ))
	[[ $seconds == *"h"* ]] && seconds=$(( ${seconds%h} * 3600 ))

	exec 50< /dev/tty50
	read -r -t $seconds -u 50
}

cat()
{
	local file
	for file
	do
		echo "$(<$file)"
	done
}

fi
