#!/bin/sh

export_top_env()
{
	export suite='sockperf'
	export testcase='sockperf'
	export category='benchmark'
	export runtime=600
	export cluster='cs-localhost'
	export job_origin='sockperf.yaml'
	export arch='x86_64'
	export node_roles='server client'
	export queue_cmdline_keys=
	export queue='ktest-cyclic'
	export testbox='lkp-icl-2sp8'
	export tbox_group='lkp-icl-2sp8'
	export branch='linus/master'
	export commit='ffd294d346d185b70e28b1a28abe367bbfe53c04'
	export repeat_to=3
	export job_file='/lkp/jobs/queued/ktest-cyclic/lkp-icl-2sp8/sockperf-cs-localhost-performance-1472b-600s-debian-12-x86_64-20240206.cgz-ffd294d346d1-20250121-579497-1d7w3db-2.yaml'
	export id='bb0809bf7d9530f2f4403f3479c5602bd5462353'
	export queuer_version='/zday/lkp'
	export model='Ice Lake'
	export nr_node=2
	export nr_cpu=64
	export memory='256G'
	export nr_ssd_partitions=3
	export nr_hdd_partitions=6
	export hdd_partitions='/dev/disk/by-id/ata-WDC_WD20SPZX-22UA7T0_WD-WX82EA06CSLM-part*'
	export ssd_partitions='/dev/disk/by-id/nvme-INTEL_SSDPE2KX020T8_PHLJ151400G62P0BGN-part1
/dev/disk/by-id/nvme-INTEL_SSDPE2KX020T8_PHLJ151400G62P0BGN-part2
/dev/disk/by-id/nvme-INTEL_SSDPE2KX020T8_PHLJ151400G62P0BGN-part3'
	export rootfs_partition='/dev/disk/by-id/nvme-INTEL_SSDPE2KX020T8_PHLJ151400G62P0BGN-part4'
	export kernel_cmdline_hw='acpi_rsdp=0x6988d014'
	export result_service='tmpfs'
	export LKP_SERVER='10.239.97.5'
	export avoid_nfs=1
	export brand='Intel(R) Xeon(R) Gold 6346 CPU @ 3.10GHz'
	export ucode='0xd0003a5'
	export rootfs='debian-12-x86_64-20240206.cgz'
	export kconfig='x86_64-rhel-9.4'
	export compiler='gcc-12'
	export _rt='/result/sockperf/cs-localhost-performance-1472b-600s/lkp-icl-2sp8/debian-12-x86_64-20240206.cgz/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04'
	export kernel='/pkg/linux/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/vmlinuz-6.13.0'
	export result_root='/result/sockperf/cs-localhost-performance-1472b-600s/lkp-icl-2sp8/debian-12-x86_64-20240206.cgz/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/1'
	export user='lkp'
	export scheduler_version='/lkp/lkp/.src-20250120-101558'
	export max_uptime=2100
	export initrd='/osimage/debian/debian-12-x86_64-20240206.cgz'
	export bootloader_append='root=/dev/ram0
RESULT_ROOT=/result/sockperf/cs-localhost-performance-1472b-600s/lkp-icl-2sp8/debian-12-x86_64-20240206.cgz/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/1
BOOT_IMAGE=/pkg/linux/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/vmlinuz-6.13.0
branch=linus/master
job=/lkp/jobs/scheduled/lkp-icl-2sp8/sockperf-cs-localhost-performance-1472b-600s-debian-12-x86_64-20240206.cgz-ffd294d346d1-20250121-579497-1d7w3db-2.yaml
user=lkp
ARCH=x86_64
kconfig=x86_64-rhel-9.4
commit=ffd294d346d185b70e28b1a28abe367bbfe53c04
intremap=posted_msi
acpi_rsdp=0x6988d014
max_uptime=2100
LKP_SERVER=10.239.97.5
nokaslr
selinux=0
debug
apic=debug
sysrq_always_enabled
rcupdate.rcu_cpu_stall_timeout=100
net.ifnames=0
printk.devkmsg=on
panic=-1
softlockup_panic=1
nmi_watchdog=panic
oops=panic
load_ramdisk=2
prompt_ramdisk=0
drbd.minor_count=8
systemd.log_level=err
ignore_loglevel
console=tty0
earlyprintk=ttyS0,115200
console=ttyS0,115200
vga=normal
rw'
	export modules_initrd='/pkg/linux/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/modules.cgz'
	export bm_initrd='/osimage/deps/debian-12-x86_64-20240206.cgz/lkp_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/rsync-rootfs_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/run-ipconfig_20241102.cgz,/osimage/pkg/debian-12-x86_64-20240206.cgz/sockperf-x86_64-ed92afb-1_20240301.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/iostat_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/perf_20241102.cgz,/osimage/pkg/debian-12-x86_64-20240206.cgz/perf-x86_64-11066801dd4b-1_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/mpstat_20240221.cgz,/osimage/pkg/debian-12-x86_64-20240206.cgz/sar-x86_64-f3f2b1a4-1_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/hw_20241102.cgz'
	export ucode_initrd='/osimage/ucode/intel-ucode-20230906.cgz'
	export lkp_initrd='/osimage/user/lkp/lkp-x86_64.cgz'
	export site='inn'
	export LKP_CGI_PORT=80
	export LKP_CIFS_PORT=139
	export job_initrd='/lkp/jobs/scheduled/lkp-icl-2sp8/sockperf-cs-localhost-performance-1472b-600s-debian-12-x86_64-20240206.cgz-ffd294d346d1-20250121-579497-1d7w3db-2.cgz'

	[ -n "$LKP_SRC" ] ||
	export LKP_SRC=/lkp/${user:-lkp}/src
}


run_job()
{
	echo $$ > $TMP/run-job.pid

	. $LKP_SRC/lib/http.sh
	. $LKP_SRC/lib/job.sh
	. $LKP_SRC/lib/env.sh

	export_top_env

	run_setup $LKP_SRC/bin/run-setup cpufreq_governor 'performance'

	run_setup $LKP_SRC/bin/run-setup sanity-check

	run_monitor $LKP_SRC/bin/run-monitor kmsg
	run_monitor $LKP_SRC/bin/run-no-stdout-monitor boot-time
	run_monitor $LKP_SRC/bin/run-monitor uptime
	run_monitor $LKP_SRC/bin/run-monitor iostat
	run_monitor $LKP_SRC/bin/run-monitor heartbeat
	run_monitor $LKP_SRC/bin/run-monitor vmstat
	run_monitor $LKP_SRC/bin/run-monitor numa-numastat
	run_monitor $LKP_SRC/bin/run-monitor numa-vmstat
	run_monitor $LKP_SRC/bin/run-monitor numa-meminfo
	run_monitor $LKP_SRC/bin/run-monitor proc-vmstat
	run_monitor $LKP_SRC/bin/run-monitor proc-stat
	run_monitor $LKP_SRC/bin/run-monitor meminfo
	run_monitor $LKP_SRC/bin/run-monitor slabinfo
	run_monitor $LKP_SRC/bin/run-monitor interrupts
	run_monitor $LKP_SRC/bin/run-monitor lock_stat
	run_monitor lite_mode=1 $LKP_SRC/bin/run-monitor perf-sched
	run_monitor $LKP_SRC/bin/run-monitor softirqs
	run_monitor $LKP_SRC/bin/run-one-shot-monitor bdi_dev_mapping
	run_monitor $LKP_SRC/bin/run-monitor diskstats
	run_monitor $LKP_SRC/bin/run-monitor nfsstat
	run_monitor $LKP_SRC/bin/run-monitor cpuidle
	run_monitor $LKP_SRC/bin/run-monitor cpufreq-stats
	run_monitor $LKP_SRC/bin/run-monitor turbostat
	run_monitor $LKP_SRC/bin/run-monitor sched_debug
	run_monitor $LKP_SRC/bin/run-monitor perf-stat
	run_monitor $LKP_SRC/bin/run-monitor mpstat
	run_monitor $LKP_SRC/bin/run-no-stdout-monitor perf-c2c
	run_monitor debug_mode=0 $LKP_SRC/bin/run-no-stdout-monitor perf-profile
	run_monitor $LKP_SRC/bin/run-monitor oom-killer
	run_monitor $LKP_SRC/bin/run-monitor watchdog

	if role server
	then
		start_daemon $LKP_SRC/bin/run-daemon sockperf-server
	fi

	if role client
	then
		run_test msg_size='1472b' $LKP_SRC/bin/run-test sockperf
	fi
}


extract_stats()
{
	export stats_part_begin=
	export stats_part_end=

	env msg_size='1472b' $LKP_SRC/bin/run-stats sockperf
	$LKP_SRC/bin/run-stats kmsg
	$LKP_SRC/bin/run-stats boot-time
	$LKP_SRC/bin/run-stats uptime
	$LKP_SRC/bin/run-stats iostat
	$LKP_SRC/bin/run-stats vmstat
	$LKP_SRC/bin/run-stats numa-numastat
	$LKP_SRC/bin/run-stats numa-vmstat
	$LKP_SRC/bin/run-stats numa-meminfo
	$LKP_SRC/bin/run-stats proc-vmstat
	$LKP_SRC/bin/run-stats meminfo
	$LKP_SRC/bin/run-stats slabinfo
	$LKP_SRC/bin/run-stats interrupts
	$LKP_SRC/bin/run-stats lock_stat
	env lite_mode=1 $LKP_SRC/bin/run-stats perf-sched
	$LKP_SRC/bin/run-stats softirqs
	$LKP_SRC/bin/run-stats diskstats
	$LKP_SRC/bin/run-stats nfsstat
	$LKP_SRC/bin/run-stats cpuidle
	$LKP_SRC/bin/run-stats cpufreq-stats
	$LKP_SRC/bin/run-stats turbostat
	$LKP_SRC/bin/run-stats sched_debug
	$LKP_SRC/bin/run-stats perf-stat
	$LKP_SRC/bin/run-stats mpstat
	$LKP_SRC/bin/run-stats perf-c2c
	env debug_mode=0 $LKP_SRC/bin/run-stats perf-profile

	$LKP_SRC/bin/run-stats time sockperf.time
	$LKP_SRC/bin/run-stats dmesg
	$LKP_SRC/bin/run-stats kmsg
	$LKP_SRC/bin/run-stats last_state
	$LKP_SRC/bin/run-stats stderr
	$LKP_SRC/bin/run-stats time
}


"$@"