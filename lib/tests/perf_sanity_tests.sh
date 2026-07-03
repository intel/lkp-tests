#!/bin/bash

. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/debug.sh

prepare_perf()
{
	set_perf_path "/lkp/benchmarks/perf/perf"

	$perf --version
}

prepare_vmlinux()
{
	local build_dir=$(readlink /lib/modules/$(uname -r)/build)
	[[ -n "$build_dir" ]] || return

	[[ -f $build_dir/vmlinux ]]
}
