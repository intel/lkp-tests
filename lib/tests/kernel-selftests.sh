#!/bin/bash

. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/tests/version.sh
. $LKP_SRC/lib/tests/update-llvm.sh
. $LKP_SRC/lib/reproduce-log.sh

build_selftests()
{
	cd tools/testing/selftests	|| return

	# temporarily workaround compile error on gcc-6
	[[ "$LKP_LOCAL_RUN" = "1" ]] && {
		# local user may contain both gcc-5 and gcc-6
		CC=$(basename $(readlink $(which gcc)))
		# force to use gcc-5 to build x86
		[[ "$CC" = "gcc-6" ]] && has_cmd gcc-5 && sed -i -e '/^include ..\/lib.mk/a CC=gcc-5' x86/Makefile
	}

	make				|| return
	cd ../../..
}

prepare_test_env()
{
	has_cmd make || return

	# lkp qemu needs linux-selftests_dir and linux_headers_dir to reproduce kernel-selftests.
	# when reproduce bug reported by kernel test robot, the downloaded linux-selftests file is stored at /usr/src/linux-selftests
	linux_selftests_dir=(/usr/src/linux-selftests-*)
	linux_selftests_dir=$(realpath $linux_selftests_dir)
	if [[ $linux_selftests_dir ]]; then
		# when reproduce bug reported by kernel test robot, the downloaded linux-headers file is stored at /usr/src/linux-headers
		linux_headers_dirs=(/usr/src/linux-headers*)

		[[ $linux_headers_dirs ]] || die "failed to find linux-headers package"
		linux_headers_dir=${linux_headers_dirs[0]}
		echo "KERNEL SELFTESTS: linux_headers_dir is $linux_headers_dir"

		# headers_install's default location is usr/include which is required by several tests' Makefile
		mkdir -p "$linux_selftests_dir/usr/include" || return
		mount --bind $linux_headers_dir/include $linux_selftests_dir/usr/include || return

		mkdir -p "$linux_selftests_dir/tools/include/uapi/asm" || return
		mount --bind $linux_headers_dir/include/asm $linux_selftests_dir/tools/include/uapi/asm || return

		local build_link="/lib/modules/$(uname -r)/build"
		ln -sf "$linux_selftests_dir" "$build_link"

		local linux_headers_bpf_dir=(/usr/src/linux-headers*-bpf)
		[[ $linux_headers_bpf_dir ]] || die "failed to find linux-headers-bpf package"
		cp -af $linux_headers_bpf_dir/* $linux_selftests_dir/

		get_kconfig $linux_selftests_dir/.config
	elif [ -d "/tmp/build-kernel-selftests/linux" ]; then
		# commit bb5ef9c change build directory to /tmp/build-$BM_NAME/xxx
		linux_selftests_dir="/tmp/build-kernel-selftests/linux"

		cd $linux_selftests_dir || return
		build_selftests
	else
		linux_selftests_dir="/lkp/benchmarks/kernel-selftests"
	fi

	# Only update llvm for bpf test
	[ "$group" = "bpf" -o "$group" = "net" -o "$group" = "tc-testing" ] && {
		prepare_for_llvm || die "install newest llvm failed"
	}

	prepare_for_commands
}

prepare_for_bpf()
{
	local modules_dir="/lib/modules/$(uname -r)"
	mkdir -p "$linux_selftests_dir/lib" || die
	if [[ "$LKP_LOCAL_RUN" = "1" ]]; then
		cp -r $modules_dir/kernel/lib/* $linux_selftests_dir/lib
	else
		# make sure the test_bpf.ko path for bpf test is right
		log_cmd mount --bind $modules_dir/kernel/lib $linux_selftests_dir/lib || die

		# required by build bpf_testmod.ko
		linux_headers_mod_dirs=(/usr/src/linux-headers*-bpf)
		linux_headers_mod_dirs=$(realpath $linux_headers_mod_dirs)
		[[ "$linux_headers_mod_dirs" ]] && export KDIR=$linux_headers_mod_dirs

		cp /sys/kernel/btf/vmlinux $linux_headers_mod_dirs

		(
			#  CLNG-BPF [test_maps] bpf_iter_task_vma.o
			# /bin/sh: 1: ./tools/bpf/resolve_btfids/resolve_btfids: not found
			cd $linux_selftests_dir &&
			make -j${nr_cpu} -C tools/bpf/resolve_btfids &&
			mkdir -p $linux_headers_mod_dirs/tools/bpf/resolve_btfids &&
			cp tools/bpf/resolve_btfids/resolve_btfids $linux_headers_mod_dirs/tools/bpf/resolve_btfids/
		)
	fi
}

prepare_for_commands()
{
	export PATH=/lkp/benchmarks/kernel-selftests/kernel-selftests/iproute2-next/sbin:$PATH
	export PATH=$BENCHMARK_ROOT/kernel-selftests/kernel-selftests/dropwatch/bin:$PATH

	# temporarily workaround compile error on gcc-6
	has_cmd gcc-5 && log_cmd ln -sf /usr/bin/gcc-5 /usr/bin/gcc
	# fix cc: command not found
	has_cmd cc || log_cmd ln -sf /usr/bin/gcc /usr/bin/cc
	# fix bpf: /bin/sh: clang: command not found
	has_cmd clang || {
		installed_clang=$(find /usr/bin -name "clang-[0-9]*")
		log_cmd ln -sf $installed_clang /usr/bin/clang
	}
	# fix bpf: /bin/sh: line 2: llc: command not found
	has_cmd llc || {
		installed_llc=$(find /usr/bin -name "llc-*")
		log_cmd ln -sf $installed_llc /usr/bin/llc
	}
	# fix bpf /bin/sh: llvm-readelf: command not found
	has_cmd llvm-readelf || {
		llvm=$(find /usr/lib -name "llvm*" -type d)
		llvm_ver=${llvm##*/}
		export PATH=$PATH:/usr/lib/$llvm_ver/bin
	}

	set_iptables_path
}

check_kconfig()
{
	local dependent_config=$1
	local kernel_config=$2

	while read line
	do
		# Avoid commentary on config
		[[ "$line" =~ ^"CONFIG_" ]] || continue

		# only kernel <= v5.0 has CONFIG_NFT_CHAIN_NAT_IPV4 and CONFIG_NFT_CHAIN_NAT_IPV6
		[[ "$line" =~ "CONFIG_NFT_CHAIN_NAT_IPV" ]] && continue

		# Some kconfigs are required as m, but they may set as y alreadly.
		# So don't check y/m, just match kconfig name
		# E.g. convert CONFIG_TEST_VMALLOC=m to CONFIG_TEST_VMALLOC=
		line="${line%=*}="
		if [[ "$line" = "CONFIG_DEBUG_PI_LIST=" ]]; then
			grep -q $line $kernel_config || {
				line="CONFIG_DEBUG_PLIST="
				grep -q $line $kernel_config || {
					echo "LKP WARN miss config $line of $dependent_config"
				}
			}
		else
			grep -q $line $kernel_config || {
				echo "LKP WARN miss config $line of $dependent_config"
			}
		fi
	done < $dependent_config
}

fixup_dma()
{
	# need to bind a device to dma_map_benchmark driver
	# for PCI devices
	local name=$(ls /sys/bus/pci/devices/ | head -1)
	[[ $name ]] || return

	echo dma_map_benchmark > /sys/bus/pci/devices/$name/driver_override || return

	local old_bind_dir=$(ls -d /sys/bus/pci/drivers/*/$name)
	[[ $old_bind_dir ]] && {
		echo $name > $(dirname $old_bind_dir)/unbind || return
	}

	echo $name > /sys/bus/pci/drivers/dma_map_benchmark/bind
}

skip_standalone_net_tests()
{
	[ "$test" ] && return # test will be run standalone

	# skip specific cases from net group
	local skip_from_net="tls fcnal-test.sh fib_nexthops.sh xfrm_policy.sh pmtu.sh"
	for i in $(echo $skip_from_net)
	do
		sed -i "s/$i//" net/Makefile
	done
}

setup_fcnal_test_atomic()
{
	# fcnal-test.sh will read environment value TESTS, otherwise
	# it will run all tests
	export TESTS=$test_atomic
}

recover_sysctl_output()
{
	# 79bf0d4a07d4 ("selftest: Fix set of ping_group_range in fcnal-test")
	# This commit hides the SYSCTL output of setting ping group.
	# Manually add it back to recover the lines.
	sed -i "/\t\${NSA_CMD} sysctl -q -w net.ipv4.ping_group_range='0 2147483647'/i \\\techo \"SYSCTL: net.ipv4.ping_group_range=0 2147483647\"\n\techo" net/fcnal-test.sh
}

fixup_hid()
{
	# make: Entering directory '/usr/src/perf_selftests-x86_64-rhel-9.4-kselftests-adc218676eef25575469234709c2d87185ca223a/tools/testing/selftests/hid'
	# Makefile:93: *** Cannot find a vmlinux for VMLINUX_BTF at any of "  ../../../../vmlinux /sys/kernel/btf/vmlinux /boot/vmlinux-6.12.0".  Stop.
	prepare_for_bpf

	# OSError: [Errno 24] Too many open files: '/sys/devices/virtual/misc/uhid/0003:0001:0002.0296/input'
	ulimit -n 102400
}

fixup_net()
{
	prepare_for_bpf

	# udpgro tests need enable bpf firstly
	# Missing xdp_dummy helper. Build bpf selftest first
	log_cmd make -j${nr_cpu} -C bpf 2>&1

	skip_standalone_net_tests

	# v4.18-rc1 introduces fib_tests.sh, which doesn't have execute permission
	# Warning: file fib_tests.sh is not executable
	# Warning: file test_ingress_egress_chaining.sh is not executable
	chmod +x net/*.sh

	ulimit -l 10240
	modprobe -q fou
	modprobe -q nf_conntrack_broadcast

	[ "$test" = "fcnal-test.sh" ] && [ "$test_atomic" ] && setup_fcnal_test_atomic
	[ "$test" = "fcnal-test.sh" ] && {
		recover_sysctl_output
		echo "timeout=2000" >> $group/settings
	}

	[[ $test = "fib_nexthops.sh" ]] && echo "timeout=3600" >> $group/settings

	[[ -d ../../net/ynl ]] && {
		log_cmd make -j${nr_cpu} -C ../../net/ynl || return
	}

	export CCINCLUDE="-I../bpf/tools/include"
	log_cmd make -j${nr_cpu} -C net 2>&1 || return
	log_cmd make install TARGETS=net INSTALL_PATH=/usr/bin/ 2>&1
}

fixup_efivarfs()
{
	[[ -d "/sys/firmware/efi" ]] || {
		echo "$FUNCNAME: no /sys/firmware/efi"
		return 1
	}

	grep -q -F -w efivarfs /proc/filesystems || modprobe efivarfs || {
		echo "$FUNCNAME: modprobe efivarfs fails"
		return 1
	}

	# if efivarfs is built-in, "modprobe efivarfs" always returns 0, but it does not means
	# efivarfs is supported since this requires some specified hardwares, such as booting from
	# uefi, so check again
	mount | grep efivarfs || log_cmd mount -t efivarfs efivarfs /sys/firmware/efi/efivars || {
		echo "$FUNCNAME: mount -t efivarfs fails"
		return 1
	}
}

fixup_pstore()
{
	[[ -e /dev/pmsg0 ]] || {
		# in order to create a /dev/pmsg0, we insert a dummy ramoops device
		# Previously, the expected device(/dev/pmsg0) isn't created on skylake(Sandy Bridge is fine) when we specify ecc=1
		# So we chagne ecc=0 instead, that's good to both skylake and sand bridge.
		# NOTE: the root cause is not clear
		modprobe ramoops mem_address=0x8000000 ecc=0 mem_size=1000000 2>&1
	}
}

fixup_ftrace()
{
	# FIX: sh: echo: I/O error
	sed -i 's/bin\/sh/bin\/bash/' ftrace/ftracetest

	# Stop tracing while reading the trace file by default
	# inspired by https://lkml.org/lkml/2021/10/26/1195
	echo 1 > /sys/kernel/debug/tracing/options/pause-on-trace
}

fixup_firmware()
{
	# As this case suggested, some distro(suse/debian) udev may have /lib/udev/rules.d/50-firmware.rules
	# which contains "SUBSYSTEM==firmware, ACTION==add, ATTR{loading}=-1", it will
	# immediately cancel all fallback requests, so here we remove it and restore after this case
	[ -e /lib/udev/rules.d/50-firmware.rules ] || return 0
	log_cmd mv /lib/udev/rules.d/50-firmware.rules . && {
		# udev have many rules located at /lib/udev/rules.d/, once those rules are changed
		# we need to restart udev service to reload the latest rules.
		if [[ -e /etc/init.d/udev ]]; then
			log_cmd /etc/init.d/udev restart
		else
			log_cmd systemctl restart systemd-udevd
		fi
	}

	sed -i "s/timeout=165/timeout=300/" firmware/settings
}

fixup_gpio()
{
	# gcc -O2 -g -std=gnu99 -Wall -I../../../../usr/include/    gpio-mockup-chardev.c ../../../gpio/gpio-utils.o ../../../../usr/include/linux/gpio.h  -lmount -I/usr/include/libmount -o gpio-mockup-chardev
	# gcc: error: ../../../gpio/gpio-utils.o: No such file or directory
	log_cmd make -j${nr_cpu} -C ../../../tools/gpio 2>&1 || return

	export CFLAGS="-I../../../../usr/include"
}

fixup_net_netfilter()
{
	# RULE_APPEND failed (No such file or directory): rule in chain BROUTING.
	# table `broute' is obsolete commands.
	update-alternatives --set ebtables /usr/sbin/ebtables-legacy

	echo "timeout=3600" >> net/netfilter/settings
	sed -ie "s/[\t[:space:]]\.\.\/\.\.\/\.\.\/samples\/pktgen\/pktgen_bench_xmit_mode_netif_receive.sh/\.\.\/\.\.\/\.\.\/\.\.\/samples\/pktgen\/pktgen_bench_xmit_mode_netif_receive.sh/g" net/netfilter/nft_concat_range.sh
}

fixup_lkdtm()
{
	# don't auto-reboot when panic
	echo 0 >/proc/sys/kernel/panic_on_oops
	echo 1800 >/proc/sys/kernel/panic

	# Enable UNWINDER_FRAME_POINTER will fix lkdtm USERCOPY_STACK_FRAME_TO and USERCOPY_STACK_FRAME_FROM fail.
	# But the kernel's overall performance will degrade by roughly 5-10%.
	# So instead of enable UNWINDER_FRAME_POINTER, comment out USERCOPY_STACK_FRAME_TO and USERCOPY_STACK_FRAME_FROM.
	sed -i '/USERCOPY_STACK_FRAME_TO/d' lkdtm/tests.txt
	sed -i '/USERCOPY_STACK_FRAME_FROM/d' lkdtm/tests.txt
}

cleanup_for_firmware()
{
	[[ -f 50-firmware.rules ]] && {
		log_cmd mv 50-firmware.rules /lib/udev/rules.d/50-firmware.rules
	}
}

fixup_memfd()
{
	# at v4.14-rc1, it introduces run_tests.sh, which doesn't have execute permission
	# here is to fix the permission
	[[ -f memfd/run_tests.sh ]] && {
		[[ -x memfd/run_tests.sh ]] || chmod +x memfd/run_tests.sh
	}

	# before v4.13-rc1, we need to compile fuse_mnt first
	# check whether there is target "fuse_mnt" at Makefile
	grep -wq '^fuse_mnt:' memfd/Makefile || return 0
	make fuse_mnt -C memfd
}

fixup_bpf()
{
	prepare_for_bpf

	log_cmd make -j${nr_cpu} -C ../../../tools/bpf/bpftool 2>&1 || return 2
	log_cmd make install -C ../../../tools/bpf/bpftool 2>&1 || return 2
	type ping6 && {
		sed -i 's/if ping -6/if ping6/g' bpf/test_skb_cgroup_id.sh 2>/dev/null
		sed -i 's/ping -${1}/ping${1%4}/g' bpf/test_sock_addr.sh 2>/dev/null
	}

	# some sh scripts actually need bash
	# ./test_libbpf.sh: 9: ./test_libbpf.sh: 0: not found
	[ "$(cmd_path bash)" = '/bin/bash' ] && [ $(readlink -e /bin/sh) != '/bin/bash' ] &&
		ln -fs bash /bin/sh

	local python_version=$(python3 --version)
	if [[ "$python_version" =~ "3.5" ]] && [[ -e "bpf/test_bpftool.py" ]]; then
		sed -i "s/res)/res.decode('utf-8'))/" bpf/test_bpftool.py
	fi

	[[ -f bpf/test_xdp_veth.sh ]] && {
		sed -i 's/\/redirect_map_0/\/xdp_redirect_map_0/g' bpf/test_xdp_veth.sh
		sed -i 's/\/redirect_map_1/\/xdp_redirect_map_1/g' bpf/test_xdp_veth.sh
		sed -i 's/\/redirect_map_2/\/xdp_redirect_map_2/g' bpf/test_xdp_veth.sh
	}

	# tools/testing/selftests/bpf/tools/sbin/bpftool
	export PATH=$linux_selftests_dir/tools/testing/selftests/bpf/tools/sbin:$PATH
}

fixup_kmod()
{
	# kmod tests failed on vm due to the following issue.
	# request_module: modprobe fs-xfs cannot be processed, kmod busy with 50 threads for more than 5 seconds now
	# MODPROBE_LIMIT decides threads num, reduce it to 10.
	sed -i 's/MODPROBE_LIMIT=50/MODPROBE_LIMIT=10/' kmod/kmod.sh

	# Although we reduce MODPROBE_LIMIT, but kmod_test_0009 sometimes timeout.
	# Reduce the number of times we run 0009.
	sed -i 's/0009\:150\:1/0009\:50\:1/' kmod/kmod.sh
}

fixup_fpu()
{
	modprobe test_fpu
}

fixup_exec()
{
	log_cmd touch ./exec/pipe
}

fixup_kexec()
{
	# test_kexec_load.sh: 126: [: x86_64: unexpected operator
	# test_kexec_file_load.sh: 99: [: x86_64: unexpected operator
	# using bash to avoid "unexpected operator" warning.
	sed -i 's/bin\/sh/bin\/bash/g' kexec/*.sh

	# tail: cannot open '/boot/vmlinuz-6.0.0' for reading: No such file or directory
	# the kernel image path on tbox is /opt/rootfs/tmp/pkg/linux/x86_64-rhel-8.3-kselftests/gcc-11/4fe89d07dcc2804c8b562f6c7896a45643d34b2f/vmlinuz-6.0.0
	local kernel_image=/boot/vmlinuz-$(uname -r)
	[[ -e $kernel_image ]] || {
		kernel_image=/opt/rootfs/tmp$(grep -o "/pkg/linux/.*/vmlinuz-[^ ]*" /proc/cmdline)
		[[ -e $kernel_image ]] || {
			echo "kernel image $kernel_image doesn't exist"
			return 1
		}

		sed -i "s|/boot/vmlinuz-\`uname -r\`|$kernel_image|g" kexec/kexec_common_lib.sh
	}
}

fixup_user_events()
{
	# user_events code changed a lot in below patchset
	# https://lore.kernel.org/all/20221205210017.23440-1-beaub@linux.microsoft.com/
	# before patch:
	#   $ find . -name user_events.h
	#   ./include/linux/user_events.h
	# after patch:
	#   $ find . -name user_events.h
	#   ./usr/include/linux/user_events.h
	#   ./include/uapi/linux/user_events.h
	#   ./include/linux/user_events.h
	[[ -f ../../../usr/include/linux/user_events.h ]] || {
		# dyn_test.c:9:10: fatal error: linux/user_events.h: No such file or directory
		# user_events do not build unless you manually install user_events.h into usr/include/linux.
		cp ../../../include/linux/user_events.h ../../../usr/include/linux/

		# avoid REMOVE usr/include/linux/user_events.h when make headers_install
		sed -i 's/headers_install\: headers/headers_install\:/' ../../../Makefile
	}
}

fixup_kvm()
{
	# SKIP - /dev/kvm not available (errno: 2)
	lsmod | grep -q 'kvm_intel' || modprobe kvm_intel
}

fixup_damon()
{
	# Warning: file debugfs_attrs.sh is not executable
	# Warning: file damos_apply_interval.py is not executable
	chmod +x damon/*.sh damon/*.py
}

prepare_for_selftest()
{
	if [[ "$group" =~ ^net ]]; then
		selftest_mfs=$(ls -d $group/Makefile)
	else
		selftest_mfs=$(find $group -name Makefile)
	fi
}

fixup_cpufreq()
{
	# cpufreq selftests runs longer on machine with large number of cpus
	echo 'timeout=600' > $group/settings
}

fixup_mm()
{
	# memory management selftests used to be named as vm selftests
	# and renamed to mm selftests in v6.3-rc1 by below commit:
	#   baa489fabd01 selftests/vm: rename selftests/vm to selftests/mm
	# the test script is still "run_vmtests.sh" after rename to mm selftests.

	local run_vmtests="run_vmtests.sh"
	[[ -f mm/run_vmtests ]] && run_vmtests="run_vmtests"
	# we need to adjust two value in vm/run_vmtests accroding to the nr_cpu
	# 1) needmem=262144, in Byte
	# 2) ./userfaultfd hugetlb *128* 32, we call it memory here, in MB
	# For 1) it indicates the memory size we need to reserve for 2), it should be 2 * memory
	# For 2) looking to the userfaultfd.c, we found that it requires the second (128 in above) parameter (memory) to meet
	# memory >= huge_pagesize * nr_cpus, more details you can refer to userfaultfd.c
	# in 0Day, huge_pagesize is 2M by default
	# currently, test case have a fixed memory=128, so if testbox nr_cpu > 64, this case will fail.
	# for example:
	# 64 < nr_cpu <= 128, memory=128*2, needmem=memory*2
	# 128 < nr_cpu < (128 + 64), memory=128*3, needmem=memory*2
	[ $nr_cpu -gt 64 ] && {
		local memory=$((nr_cpu/64+1))
		memory=$((memory*128))
		sed -i "s#./userfaultfd hugetlb 128 32#./userfaultfd hugetlb $memory 32#" mm/$run_vmtests
		memory=$((memory*1024*2))
		sed -i "s#needmem=262144#needmem=$memory#" mm/$run_vmtests
	}

	# vmalloc stress prepare
	if [[ $test = "vmalloc-stress" ]]; then
		# iterations or nr_threads if not set, use default value
		[[ -z $iterations ]] && iterations=20
		[[ -z $nr_threads ]] && nr_threads="\$NUM_CPUS"
		[[ $iterations -le 0 || ($nr_threads != "\$NUM_CPUS" && $nr_threads -le 0) ]] && die "Paramters: iterations or nr_threads must > 0"
		sed -i 's/^STRESS_PARAM="nr_threads=$NUM_CPUS test_repeat_count=20"/STRESS_PARAM="nr_threads='$nr_threads' test_repeat_count='$iterations'"/' mm/test_vmalloc.sh
	fi

	# vm selftests may needs to run for more than 150s on some specific platforms and exceeds the default timeout 45s
	echo 'timeout=600' > mm/settings
}

fixup_x86()
{
	# List cpus that supported SGX
	# https://ark.intel.com/content/www/us/en/ark/search/featurefilter.html?productType=873&2_SoftwareGuardExtensions=Yes%20with%20Intel%C2%AE%20ME&1_Filter-UseConditions=3906
	# If cpu support SGX, also need open SGX in bios
	grep -qw sgx x86/Makefile && {
		grep -qw sgx /proc/cpuinfo || echo "Current host doesn't support sgx"
	}

	return 0
}

fixup_livepatch()
{
	# livepatch check if dmesg meet expected exactly, so disable redirect stdout&stderr to kmsg
	[[ -s "/tmp/pid-tail-global" ]] && cat /tmp/pid-tail-global | xargs kill -9 && echo "" >/tmp/pid-tail-global

	return 0
}

fixup_mount_setattr()
{
	# fix no real run for mount_setattr
	grep -q TEST_PROGS mount_setattr/Makefile ||
		grep "TEST_GEN_FILES +=" mount_setattr/Makefile | sed 's/TEST_GEN_FILES/TEST_PROGS/' >> mount_setattr/Makefile
}

fixup_tc_testing()
{
	# Suggested by the author
	# upstream commit: https://git.kernel.org/netdev/net/c/bdf1565fe03d
	sed -i 's/"matchPattern": "qdisc pfifo_fast 0: parent 1:\[1-9,a-f\].*/"matchPattern": "qdisc [a-zA-Z0-9_]+ 0: parent 1:[1-9,a-f][0-9,a-f]{0,2}",/g' tc-testing/tc-tests/qdiscs/mq.json
	sed -i 's/"matchPattern": "qdisc pfifo_fast 0: parent 1:\[1-4\].*/"matchPattern": "qdisc [a-zA-Z0-9_]+ 0: parent 1:[1-4]",/g' tc-testing/tc-tests/qdiscs/mq.json

	# Be compatible with the *new* tc output
	# old tc output:   action order 1: bpf action.o:[action-ok] id 60 tag bcf7977d3b93787c jited default-action pipe
	# newer tc output: action order 1: bpf action.o:[action-ok] id 64 name  tag bcf7977d3b93787c jited default-action pipe
	# upstream commit: https://git.kernel.org/netdev/net/c/ac2944abe4d7
	sed -i 's/\[0-9\]\* tag/[0-9].* tag/g' tc-testing/tc-tests/actions/bpf.json
	# As description of tdc_config.py, we can replace our own tc and ip
	# $ grep sbin/tc -B1 tdc_config.py
	#  # Substitute your own tc path here
	#  'TC': '/sbin/tc',
	if [ -e /lkp/benchmarks/kernel-selftests/kernel-selftests/iproute2-next/sbin/tc ]; then
		sed -i s,/sbin/tc,/lkp/benchmarks/kernel-selftests/kernel-selftests/iproute2-next/sbin/tc,g tc-testing/tdc_config.py
		sed -i s,/sbin/ip,/lkp/benchmarks/kernel-selftests/kernel-selftests/iproute2-next/sbin/ip,g tc-testing/tdc_config.py
	fi

	modprobe netdevsim
}

build_tools()
{

	make allyesconfig		|| return
	make prepare			|| return
	# install cpupower command
	cd tools/power/cpupower		|| return
	make 				|| return
	make install			|| return
	cd ../../..
}

install_selftests()
{
	local header_dir="/tmp/linux-headers"

	mkdir -p $header_dir
	make headers_install INSTALL_HDR_PATH=$header_dir

	mkdir -p $BM_ROOT/usr/include
	cp -af $header_dir/include/* $BM_ROOT/usr/include

	mkdir -p $BM_ROOT/tools/include/uapi/asm
	cp -af $header_dir/include/asm/* $BM_ROOT/tools/include/uapi/asm

	mkdir -p $BM_ROOT/tools/testing/selftests
	cp -af tools/testing/selftests/* $BM_ROOT/tools/testing/selftests
}

pack_selftests()
{
	{
		echo /usr
		echo /usr/lib
		find /usr/lib/libcpupower.*
		echo /usr/bin
		echo /usr/bin/cpupower
		echo /lkp
		echo /lkp/benchmarks
		echo /lkp/benchmarks/$BM_NAME
		find /lkp/benchmarks/$BM_NAME/*
	} |
	cpio --quiet -o -H newc | gzip -n -9 > /lkp/benchmarks/${BM_NAME}.cgz
	[[ $arch ]] && mv "/lkp/benchmarks/${BM_NAME}.cgz" "/lkp/benchmarks/${BM_NAME}-${arch}.cgz"
}

fixup_test_group()
{
	local group=$1

	if [[ "$group" = "tc-testing" ]]; then
		fixup_tc_testing || return
	elif [[ $(type -t "fixup_${group//\//_}") = function ]]; then
		fixup_${group//\//_} || return
	fi

	# update Makefile to run the specified $test only
	[[ "$test" ]] || return 0

	local makefile=$group/Makefile
	[[ -f $makefile ]] || return

	# it overwrites the target in Makefile to keep the specified $test only
	#@@ -40,6 +40,9 @@ TEST_GEN_PROGS = reuseport_bpf reuseport_bpf_cpu reuseport_bpf_numa
	# TEST_GEN_PROGS += reuseport_dualstack reuseaddr_conflict tls
	#
	#  TEST_FILES := settings
	#
	#   KSFT_KHDR_INSTALL := 1
	#  +TEST_GEN_PROGS =
	#  +TEST_PROGS = tls
	#    include ../lib.mk
	sed -i "/^include .*\/lib.mk/i TEST_GEN_PROGS =" $makefile
	sed -i "/^include .*\/lib.mk/i TEST_PROGS = $test" $makefile
}

check_test_group_kconfig()
{
	local group=$1

	local kernel_config="/lkp/kernel-selftests-kernel-config"
	get_kconfig "$kernel_config" || return

	local group_config
	for group_config in "$group/config" "$group/config.x86_64" "$group/config.common"
	do
		# bpf/config.x86_64
		# hid/config.common
		[[ -s "$group_config" ]] && check_kconfig "$group_config" "$kernel_config"
	done

	return 0
}

prepare_tests()
{
	prepare_test_env || die "prepare test env failed"

	cd $linux_selftests_dir/tools/testing/selftests || die

	prepare_for_selftest

	[ -n "$selftest_mfs" ] || die "empty selftest_mfs"
}

run_tests()
{
	local selftest_mfs=$@

	# kselftest introduced runner.sh since kernel commit 42d46e57ec97 "selftests: Extract single-test shell logic from lib.mk"
	[[ -e kselftest/runner.sh ]] && log_cmd sed -i 's/default_timeout=45/default_timeout=300/' kselftest/runner.sh

	for mf in $selftest_mfs; do
		local group=${mf%/Makefile}

		check_test_group_kconfig $group

		fixup_test_group $group
		local exit_status=$?
		[[ $exit_status = 2 ]] && return $exit_status
		[[ $exit_status = 0 ]] || die "fixup_$group failed as $exit_status"

		log_cmd make -j${nr_cpu} TARGETS=$group 2>&1

		# vmalloc performance and stress, can not use 'make run_tests' to run
		if [[ $test =~ ^vmalloc\-(performance|stress)$ ]]; then
			log_cmd mm/test_vmalloc.sh ${test##vmalloc-} 2>&1
			log_cmd dmesg | grep -E '(Summary|All test took)' 2>&1
		elif [[ $group = resctrl ]]; then
			log_cmd resctrl/resctrl_tests 2>&1
		elif [[ $group = bpf ]]; then
			# Order correspond to 'make run_tests' order
			# TEST_GEN_PROGS = test_verifier test_tag test_maps test_lru_map test_lpm_map test_progs \
			# 		test_verifier_log test_dev_cgroup \
			# 		test_sock test_sockmap get_cgroup_id_user \
			# 		test_cgroup_storage \
			# 		test_tcpnotify_user test_sysctl \
			# 		test_progs-no_alu32

			# remove test_progs and test_progs-no_alu32 from Makefile and run them separately
			if grep -q "test_progs-no_alu32 \\\\" bpf/Makefile; then
				sed -i 's/test_progs //' bpf/Makefile
				sed -i 's/test_progs-no_alu32 //' bpf/Makefile
			else
				sed -i 's/test_lpm_map test_progs //' bpf/Makefile
				sed -i 's/test_progs-no_alu32/test_lpm_map/' bpf/Makefile
			fi

			log_cmd make quicktest=1 run_tests -C $group 2>&1

			if [[ -f bpf/test_progs && -f bpf/test_progs-no_alu32 ]]; then
				cd bpf
				echo "# selftests: bpf: test_progs"
				log_cmd ./test_progs -b sk_assign -b xdp_bonding -b get_branch_snapshot -b perf_branches -b perf_event_stackmap -b snprintf_btf
				log_cmd ./test_progs -a get_branch_snapshot -a perf_branches -a perf_event_stackmap -a snprintf_btf
				echo "# selftests: bpf: test_progs-no_alu32"
				log_cmd ./test_progs-no_alu32 -b sk_assign -b xdp_bonding -b get_branch_snapshot -b perf_branches -b perf_event_stackmap -b snprintf_btf
				log_cmd ./test_progs-no_alu32 -a perf_branches -a perf_event_stackmap -a snprintf_btf
				cd ..
			else
				echo "build bpf/test_progs or bpf/test_progs-no_alu32 failed" >&2
			fi
		elif [[ $category = "functional" ]]; then
			log_cmd make quicktest=1 run_tests -C $group 2>&1
		else
			log_cmd make run_tests -C $group 2>&1
		fi

		cleanup_test_group $group
	done
}

cleanup_test_group()
{
	local group=$1

	if [[ "$group" = "firmware" ]]; then
		cleanup_for_firmware
	fi
}
