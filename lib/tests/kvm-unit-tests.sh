#!/bin/sh

#if we pass 'hyperv_synic' to this function, line 7 - 12 will be deleted
#
# ~/lkp/kvm-unit-tests$ cat unittests.cfg -n
#  1 [vmx_null]
#  2 file = vmx.flat
#  3 extra_params = -cpu host,+vmx -append null
#  4 arch = x86_64
#  5 groups = vmx
#  6
#  7 [hyperv_synic]
#  8 file = hyperv_synic.flat
#  9 smp = 2
# 10 extra_params = -cpu kvm64,hv_synic -device hyperv-testdev
# 11 groups = hyperv
# 12
# 13 [hyperv_connections]
# 14 ...
. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/install.sh
. $LKP_SRC/lib/reproduce-log.sh

remove_case()
{
	local to_be_removed=$1
	local casesfile="x86/unittests.cfg"

	sl=$(grep "^\[$to_be_removed\]" $casesfile -n | awk -F':' '{print $1}')
	[ -n "$sl" ] || return
	el=$(sed -n "$((sl + 1)),$ p" $casesfile | grep '^\[' -n -m 1 | awk -F':' '{print $1}')

	if [ -z "$el" ]; then
		sed -i "$sl,$ d" $casesfile # delete $sl to the end
	else
		el=$((el + sl - 1))
		sed -i "$sl,$el d" $casesfile # delete $sl to $el
	fi
}

# fix issue:
# SKIP access-reduced-maxphyaddr (/sys/module/kvm_intel/parameters/allow_smaller_maxphyaddr not equal to Y)
# SKIP pmu_emulation (/sys/module/kvm/parameters/force_emulation_prefix not equal to Y)
# SKIP vmx (/sys/module/kvm_intel/parameters/nested not equal to Y)
load_kvm_param()
{
	[ -c "/dev/kvm" ] && {
		modprobe -r kvm_intel || return
		modprobe -r kvm || return
	}

	# need to run kvm_intel first
	# otherwise it may occur 'modprobe: ERROR: could not insert 'kvm': Invalid argument' issue
	modprobe kvm_intel nested=Y allow_smaller_maxphyaddr=Y || return
	modprobe kvm enable_vmware_backdoor=Y force_emulation_prefix=Y || return

	return 0
}

setup_test_environment()
{
	# fix "SKIP pmu (/proc/sys/kernel/nmi_watchdog not equal to 0)"
	[ "$(cat /proc/sys/kernel/nmi_watchdog)" != "0" ] && {
		echo 0 >/proc/sys/kernel/nmi_watchdog || return
	}
	is_virt || load_kvm_param

	return 0
}

fixup_tests()
{
	# errata.txt and run_tests.sh are under same directory, using
	# absolute path for errata.sh will increase the risk of missing
	# file, here we directly use relative path.
	sed -i 's/\(ERRATATXT=\).*/\1errata.txt/' config.mak

	# Fix timeout issue in kvm-unit-tests-qemu
	# 	'FAIL vmx_pf_exception_test_reduced_maxphyaddr (timeout; duration=90s)'
	# we should keep same setting for bare metal
	sed -i '/\[vmx_pf_exception_test_reduced_maxphyaddr\]/a\timeout = 240' x86/unittests.cfg
}

run_tests()
{
	log_cmd ./run_tests.sh
}

upload_test_results()
{
	upload_files -t results $BENCHMARK_ROOT/kvm-unit-tests/logs/*
}

dump_qemu()
{
	# dump debug info
	ldd $QEMU
	lsmod
}
