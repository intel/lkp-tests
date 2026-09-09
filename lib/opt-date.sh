#!/bin/bash

# convert a `-d` option value like 3d/2w/1m into a day count
opt_date_to_days()
{
	local opt_date=$1

	[[ $opt_date =~ [0-9]+d$ ]] && opt_date=${opt_date%d}
	[[ $opt_date =~ [0-9]+w$ ]] && opt_date=$((${opt_date%w} * 7))
	[[ $opt_date =~ [0-9]+m$ ]] && opt_date=$((${opt_date%m} * 30))

	echo "$opt_date"
}
