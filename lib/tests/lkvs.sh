#!/bin/bash

. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/run.sh

build_libipt()
{
	cd_benchmark $suite/libipt

	cmake . && make install
}

build_accel_config()
{
	cd_benchmark $suite/lkvs/BM/tools/idxd-config

	log_cmd ./autogen.sh 2>&1 || {
		echo "accel_config autogen fail"
		return 1
	}

	log_cmd ./configure CFLAGS='-g -O2' --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib64 --enable-test=yes
	log_cmd make && make install

	return 0
}

build_lkvs_tools()
{
	cd_benchmark $suite/lkvs/BM/tools

	log_cmd make --keep-going 2>&1 || {
		echo "tools make fail"
		return 1
	}

	return 0
}

build_lkvs()
{
	build_lkvs_tools || return

	# BM/dsa need accel-config tool
	[[ $test = dsa ]] && build_accel_config

	# only BM/pt needs the 3rd party library libipt
	[[ $test = pt ]] && build_libipt

	[[ -f $BENCHMARK_ROOT/$suite/lkvs/BM/$test/Makefile ]] || return 0

	cd_benchmark $suite/lkvs/BM/$test

	log_cmd make --keep-going 2>&1 || {
		echo "$test make fail"
		return 1
	}

	[[ $test = ras ]] && log_cmd make install

	return 0
}

fixup_tdx_compliance()
{
	log_cmd insmod tdx-compliance/tdx-compliance.ko
	echo all >/sys/kernel/debug/tdx/tdx-tests
	log_cmd cat /sys/kernel/debug/tdx/tdx-tests
}

fixup_splitlock()
{
	cat /proc/cpuinfo | grep -q split_lock_detect || die "split_lock_detect not supported on current CPU"
}

fixup_rapl_server()
{
	log_cmd modprobe -v intel_rapl_msr
}

alias fixup_rapl_client=fixup_rapl_server

runtests()
{
	# for glxgears on centos, which is located at /usr/lib64/mesa/glxgears
	export PATH="$PATH:/usr/lib64/mesa"
	# libipt.so.2 is installed in /usr/local/lib or /usr/local/lib64
	export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
	export LD_LIBRARY_PATH=/usr/local/lib64:$LD_LIBRARY_PATH

	cd_benchmark $suite/lkvs/BM

	if [[ $(type -t "fixup_${test//-/_}") =~ (alias|function) ]]; then
		fixup_${test//-/_} || return
	fi

	if [[ -f $test/tests ]]; then
		log_cmd ./runtests -f $test/tests
	else
		case $test in
		cstate-client)
			log_cmd ./runtests -f cstate/tests-client
			;;
		cstate-server)
			log_cmd ./runtests -f cstate/tests-server
			;;
		prefetchi)
			log_cmd prefetchi/prefetchi
			;;
		rapl-client)
			log_cmd ./runtests -f rapl/tests-client
			;;
		rapl-server)
			log_cmd ./runtests -f rapl/tests-server
			;;
		th)
			log_cmd ./runtests -c "th/th_test 1"
			log_cmd ./runtests -c "th/th_test 2"
			;;
		topology-client)
			log_cmd ./runtests -f topology/tests-client
			;;
		topology-server)
			log_cmd ./runtests -f topology/tests-server
			;;
		*)
			die "unknown $test"
			;;
		esac
	fi
}
