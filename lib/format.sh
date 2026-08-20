#!/bin/bash

humanize_time()
{
	local seconds=$1

	local days=$((seconds / 86400))
	local hours=$(((seconds % 86400) / 3600))
	local minutes=$(((seconds % 3600) / 60))

	local result=""
	[[ $days -gt 0 ]] && result+="${days}d "
	[[ $hours -gt 0 ]] && result+="${hours}h "
	[[ $minutes -gt 0 ]] && result+="${minutes}m"

	echo "$result"
}
