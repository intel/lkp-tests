#!/bin/bash

# greater than or equal
libc_version_ge()
{
	local version=$1
	# debian: /lib/x86_64-linux-gnu/libc.so.6
	# /lib/x86_64-linux-gnu/libc.so.6
	# GNU C Library (Ubuntu GLIBC 2.27-3ubuntu1.4) stable release version 2.27.
	# printf '2.4.5\n2.8\n2.4.5.1\n' | sort -V
	[[ -f /lib/x86_64-linux-gnu/libc.so.6 ]] && libc_bin=/lib/x86_64-linux-gnu/libc.so.6

	# fedora: /usr/lib/libc.so.6
	# [root@iaas-rpma proc]# /usr/lib/libc.so.6
	# GNU C Library (GNU libc) stable release version 2.32.
	[[ -f /usr/lib/libc.so.6 ]] && libc_bin=/usr/lib/libc.so.6
	[[ "$libc_bin" ]] || return 0

	local local_version=$($libc_bin | head -1 | awk '{print $NF}')
	local_version=${local_version::-1} # omit the last .
	local greatest=$(printf "$local_version\n$1" | sort -V | head -1)

	[[ "$greatest" = "$version" ]]
}

get_kernel_version()
{
	# 5.14.9-200.fc34.x86_64
	# format: X.Y.Z-...
	local version=$(uname -r)
	# 5.14.9
	# format: X.Y.Z
	version=${version%%-*}
	# 5.14
	# format: X.Y
	version=${version%.*}

	echo $version
}

is_kernel_version_ge()
{
	local other=$1
	local version=$(get_kernel_version)

	rs_value=$(awk -v version=${version} -v other=${other} 'BEGIN { print(version >= other) ? "0" : "1" }')
	return $rs_value
}

is_kernel_version_gt()
{
	local other=$1
	local version=$(get_kernel_version)

	rs_value=$(awk -v version=${version} -v other=${other} 'BEGIN { print(version > other) ? "0" : "1" }')
	return $rs_value
}
