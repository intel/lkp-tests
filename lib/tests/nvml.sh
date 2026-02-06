#!/bin/bash

. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/run.sh

check_group_param()
{
	cd_benchmark $suite/src/test

	[[ -n "$group" ]] || die "Parameter \"group\" is empty"

	if [[ $group =~ _ ]]; then
		if [[ -d "$group" ]]; then
			testcases=$group
		else
			die "single test $group is not found"
		fi
	else
		testcases=$(ls -d "$group"_* 2>/dev/null)
	fi

	# Some testcase is contianed in folder named by $group (such as traces).
	# Adding it into testcases. We think it's a testcase if there is a TEST0 or TESTS.py in the folder.
	[[ -f "$group/TEST0" || -f "$group/TESTS.py" ]] && [[ ! $group =~ _ ]] && testcases+=" $group"
	[[ -n "$testcases" ]] || die "Parameter group $group is invalid"
}

check_test_param()
{
	if [[ "$test" = "non-pmem" ]] || [[ "$test" = "pmem" ]] || [[ "$test" = "none" ]]; then
		tmp_dir=$(mktemp -d)
		echo "NON_PMEM_FS_DIR=$tmp_dir" > testconfig.sh
		echo "PMEM_FS_DIR=/fs/pmem0" >> testconfig.sh
		echo "ENABLE_NFIT_TESTS=y" >> testconfig.sh
		mkdir -p /fs/pmem0
	else
		die "Parameter \"test\" is wrong"
	fi
}

setup_compiler()
{
	log_cmd export CC=clang
	log_cmd export CXX=clang++
}

build_env()
{
	cd_benchmark

	setup_compiler

	# ./check_max_mmap.sh: line 44: /build/nvml/src/src/test/tools/anonymous_mmap/../../testconfig.sh: No such file or directory
	[ -f src/test/testconfig.sh ] || log_cmd cp src/test/testconfig.sh.example src/test/testconfig.sh
	# Please add valid testconfig.py file - see testconfig.py.example
	[ -f src/test/testconfig.py ] || log_cmd cp src/test/testconfig.py.example src/test/testconfig.py
	# clear CFLAGS and CXXFLAGS to avoid unknown arguments
	# clang-8: error: unknown argument: '-ftree-loop-distribute-patterns'
	# clang-8: error: unknown argument: '-fno-semantic-interposition'
	CFLAGS=""
	CXXFLAGS=""

	# To fix the error with aliyun rootfs:
	# src/common.inc:366: *** Please install libndctl-dev/libndctl-devel >= 63.  Stop.
	is_aliyunos && log_cmd export PKG_CONFIG_PATH="$PKG_CONFIG_PATH":/usr/local/lib/pkgconfig/

	# force to set OS_DIMM to avoid the below errors:
	# /usr/bin/ld: ../../../src/../src/debug/libpmemcommon.a(libpmemcommon_all.o): in function `pmem2_badblock_context_new':
	# /lkp/benchmarks/nvml/src/common/../../src/../src/libpmem2/badblocks_ndctl.c:281: undefined reference to `pmem2_region_namespace'
	log_cmd export OS_DIMM=ndctl

	# All C++ container tests need customized version of libc --libc++ to compile. So specify the path of libc++ to make.
	log_cmd make -j${nr_cpu} EXTRA_CFLAGS="-DPAGE_SIZE=4096 -DUSE_VALGRIND -Wno-error" USE_LLVM_LIBCPP=1 LIBCPP_INCDIR=/usr/local/libcxx/include/c++/v1/ LIBCPP_LIBDIR=/usr/local/libcxx/lib || return
	log_cmd make -j${nr_cpu} EXTRA_CFLAGS="-DPAGE_SIZE=4096 -DUSE_VALGRIND -Wno-error" USE_LLVM_LIBCPP=1 LIBCPP_INCDIR=/usr/local/libcxx/include/c++/v1/ LIBCPP_LIBDIR=/usr/local/libcxx/lib test
}

enable_remote_node()
{
	cd_benchmark $suite/src/test

	# To fix no nodes provide. It takes another machines as remote nodes. We can use
	# localhost as remote node but need to do some configs as below.
	# reference on follow link
	# https://github.com/pmem/nvml/blob/3ab708efad653aeda0bcbc6b8d2b61d9ba9d5310/utils/docker/configure-tests.sh#L53
	for n in {0..3}
	do
		echo "NODE[$n]=127.0.0.1" >> testconfig.sh
		echo "NODE_WORKING_DIR[$n]=/tmp/node$n" >> testconfig.sh
		echo "NODE_ADDR[$n]=127.0.0.1" >> testconfig.sh
		echo "NODE_ENV[$n]=\"PMEM_IS_PMEM_FORCE=1\"" >> testconfig.sh
	done

	echo "TEST_PROVIDERS=sockets" >> testconfig.sh
	# enable ssh localhost without password
	pgrep -l sshd || die "ssh server do not run"

	log_cmd ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa

	log_cmd cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

	expect -c "set timeout -1;
        spawn ssh 127.0.0.1 exit;
        expect {
            *(yes/no*)* {send -- yes\r;exp_continue;}
        }";

	return 0
}

setup_mount_loop_dev()
{
	[[ -d "$tmp_dir" ]] || return
	truncate --size 200M /tmp/loop-file
	losetup loop0 /tmp/loop-file
	mkfs.ext4 /dev/loop0 &>/dev/null
	mount /dev/loop0 $tmp_dir
}

umount_loop_dev()
{
	[[ -d "$tmp_dir" ]] || return
	umount $tmp_dir
	losetup -d /dev/loop0
}

run()
{
	local user_filter="$BENCHMARK_ROOT/$suite/user_filter"
	local testcase=
	local test_cmd=

	cd_benchmark $suite/src/test

	# to fix SKIP: C++11 required
	log_cmd export CXX=g++
	log_cmd ln -sf /usr/local/bin/ndctl /usr/bin/ndctl

	# enable remote valgrind test
	echo "RPMEM_VALGRIND_ENABLED=y" >> testconfig.sh

	# to fix no point to a PMEM device
	echo "PMEM_FS_DIR_FORCE_PMEM=1" >> testconfig.sh

	[ "$test" = "pmem" ] && echo "PMEM_FS_DIR_FORCE_PMEM=2" >> testconfig.sh
	for testcase in $testcases
	do
		test_cmd="./RUNTESTS.sh -f $test"
		# If exist TESTS.py, call RUNTESTS.py to run tests
		[[ -x "$testcase/TESTS.py" ]] && test_cmd="./RUNTESTS.py"

		# fix util_extent/TEST0: SKIP file system tmpfs (ext4 required)
		[[ "$testcase" = "util_extent" ]] && [[ "$test" = "non-pmem" ]] && setup_mount_loop_dev

		# export this env variable to enable obj_tx_a* tests
		[[ $testcase =~ obj_tx_a ]] && export MALLOC_MMAP_THRESHOLD_=0

		if [ "$LKP_LOCAL_RUN" != "1" ] && [[ -s "$user_filter" ]] && grep -w -q "$testcase" "$user_filter"; then
			log_cmd chown lkp:lkp -R $BENCHMARK_ROOT/$casename
			log_cmd chown lkp:lkp -R /tmp
			log_cmd chown lkp:lkp -R /fs/pmem0
			log_eval su lkp -c "$test_cmd $testcase  2>&1"
		else
			log_eval $test_cmd $testcase  2>&1
		fi

		# unset env variable in case it do impact on other tests
		[[ $testcase =~ obj_tx_a ]] && unset MALLOC_MMAP_THRESHOLD_
		[[ "$testcase" = "util_extent" ]] && [[ "$test" = "non-pmem" ]] && umount_loop_dev
	done

	return 0
}

# Automatically detect and generate new groups for each fs-types
build_generate_testgroup()
{
	cd "$source_dir/src/test" || return
	rm -f group_none group_non-pmem group_pmem group_by_fs_type.yaml

	# 1.find out the groups
	#   directoy obj_bucket, obj_list, blk_pool,blk_nblock will be treat as two
	#   groups named obj and blk that we can find at LKP_SRC/job/nvml.yaml
	# 2.find out the fs-type for each 2. find out the fs-type for each groupgroup
	#   travel $group/TESTx, it will match one of bellow rule
	#     a. keyword: require_fs_type none  -> put into fs_type none
	#     b. keyword: require_fs_type non-pmem -> put into fs_type non-pmem
	#     c. keyword: require_fs_type pmem -> put into fs_type pmem
	#     d. keyword: require_fs_type any -> put into fs_type both non-pmem and pmem
	#     e. no keyword 'require_fs_type' -> put into fs_type both non-pmem and pmem
	for nvml_case in *
	do
		[ -f "$nvml_case/TEST0" ] || continue
		[ -x "$nvml_case/TEST0" ] || continue
		cd "$nvml_case" || continue
		scripts=$(ls -1 TEST* | grep -v -i -e "\.ps1" | sort -V)

		for run_script in $scripts
		do
			req_fs=$(grep -w "require_fs_type" "$run_script") || {
				echo  "$nvml_case" >> ../group_pmem
				echo  "$nvml_case" >> ../group_non-pmem
				continue
			}
			fs_type=${req_fs:15}
			for type in $fs_type
			do
				case "$type"
				in
				any)
					echo "$nvml_case" >> ../group_pmem
					echo "$nvml_case" >> ../group_non-pmem
					;;
				non-pmem)
					echo "$nvml_case" >>../group_non-pmem
					;;
				pmem)
					echo "$nvml_case" >>../group_pmem
					;;
				none)
					echo "$nvml_case" >>../group_none
					;;
				esac
			done
		done
		cd - >/dev/null || return
	done
	for type in pmem non-pmem none
	do
	    echo "$type:" >> group_by_fs_type.yaml
	    awk -F '_' '{print $1}' group_$type | sort -u | sed 's/^/  - /g'>> group_by_fs_type.yaml
	done
	rm -f group_none group_non-pmem group_pmem
	return 0
}

# Auto generate user_filter to enable those tests which do not need run as superuser.
build_user_filter_file()
{
	cd "$source_dir" || return
	git grep "require_no_superuser" | awk -F '[:/]' '{if (!a[$3]++ && $3 != "unittest") {print $3} }' > user_filter
}
