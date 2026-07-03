#!/bin/bash

lkp_src()
{
	local lkp_src="$LKP_SRC"

	local str
	for str in "$@"; do
		lkp_src="$lkp_src/$str"
	done

	echo "$lkp_src"
}
