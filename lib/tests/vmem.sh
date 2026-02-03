#!/bin/bash

. $LKP_SRC/lib/tests/nvml.sh
. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/debug.sh

check_vmem_param()
{
	local casename=$1

	log_cmd cd "$BENCHMARK_ROOT/$casename/src/test" || die "Can not find $casename/src/test dir"

	if [[ "$group" = "vmem" ]]; then
		echo "DEVICE_DAX_PATH=(/dev/dax0.0)" > testconfig.sh
	fi

	tmp_dir=$(mktemp -d)
	echo "TEST_DIR=$tmp_dir" >> testconfig.sh

	[[ -n "$group" ]] || die "Parameter \"group\" is empty"

	testcases=$(ls -d "$group"_* 2>/dev/null)

	# Some testcase is contianed in folder named by $group (such as traces).
	# Adding it into testcases. We think it's a testcase if there is a TEST0 in the folder.
	[[ -f "$group/TEST0" ]] && testcases+=" $group"
	[[ -n "$testcases" ]] || die "Parameter \"group\" is invalid"
}

build_vmem_env()
{
	local casename=$1

	log_cmd cd "$BENCHMARK_ROOT/$casename"

	setup_compiler

	make test || return
}

run_vmem()
{
	local casename=$1
	local testcase=

	if [ "$LKP_LOCAL_RUN" != "1" ]; then
		log_cmd chown lkp:lkp -R "$BENCHMARK_ROOT/$casename"
		log_cmd chown lkp:lkp -R /tmp
		[[ "$group" == *"vmem"* ]] && log_cmd chown lkp:lkp -R /dev/dax0.0
	fi

	log_cmd cd "$BENCHMARK_ROOT/$casename/src/test"
	for testcase in $testcases
	do
		if [ "$LKP_LOCAL_RUN" != "1" ]; then
			log_cmd su lkp -c "./RUNTESTS $testcase  2>&1"
		else
			log_cmd ./RUNTESTS $testcase  2>&1
		fi
	done

	return 0
}
