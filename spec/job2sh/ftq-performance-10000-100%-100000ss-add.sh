#!/bin/sh

export_top_env()
{
	export suite='ftq'
	export testcase='ftq'
	export category='noise-benchmark'
	export nr_task=4
	export samples='100000ss'
	export job_origin='ftq.yaml'
	export arch='x86_64'
	export queue_cmdline_keys=
	export queue='ktest-cyclic'
	export testbox='lkp-ivb-d04'
	export tbox_group='lkp-ivb-d04'
	export branch='linus/master'
	export commit='ffd294d346d185b70e28b1a28abe367bbfe53c04'
	export repeat_to=1
	export job_file='/lkp/jobs/queued/ktest-cyclic/lkp-ivb-d04/ftq-performance-10000-100%-100000ss-add-debian-12-x86_64-20240206.cgz-ffd294d346d1-20250123-611007-2sqd4l-0.yaml'
	export id='ad86f0776125269c943d861affd71b24f278ff1e'
	export queuer_version='/zday/lkp'
	export model='Ivy Bridge'
	export nr_node=1
	export nr_cpu=4
	export memory='8G'
	export nr_ssd_partitions=1
	export nr_hdd_partitions=4
	export ssd_partitions='/dev/disk/by-id/ata-INTEL_SSDSC2KB240G8_BTYF836606UQ240AGN-part1'
	export hdd_partitions='/dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M0KTT6NK-part2 /dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M0KTT6NK-part3 /dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M0KTT6NK-part4 /dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M0KTT6NK-part5'
	export rootfs_partition='/dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M0KTT6NK-part1'
	export brand='Intel(R) Core(TM) i3-3220 CPU @ 3.30GHz'
	export netconsole_port=6676
	export ucode='0x21'
	export rootfs='debian-12-x86_64-20240206.cgz'
	export kconfig='x86_64-rhel-9.4'
	export compiler='gcc-12'
	export _rt='/result/ftq/performance-10000-100%-100000ss-add/lkp-ivb-d04/debian-12-x86_64-20240206.cgz/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04'
	export kernel='/pkg/linux/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/vmlinuz-6.13.0'
	export result_root='/result/ftq/performance-10000-100%-100000ss-add/lkp-ivb-d04/debian-12-x86_64-20240206.cgz/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/0'
	export user='lkp'
	export LKP_SERVER='internal-lkp-server'
	export scheduler_version='/lkp/lkp/.src-20250122-221107'
	export max_uptime=2100
	export initrd='/osimage/debian/debian-12-x86_64-20240206.cgz'
	export bootloader_append='root=/dev/ram0
RESULT_ROOT=/result/ftq/performance-10000-100%-100000ss-add/lkp-ivb-d04/debian-12-x86_64-20240206.cgz/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/0
BOOT_IMAGE=/pkg/linux/x86_64-rhel-9.4/gcc-12/ffd294d346d185b70e28b1a28abe367bbfe53c04/vmlinuz-6.13.0
branch=linus/master
job=/lkp/jobs/scheduled/lkp-ivb-d04/ftq-performance-10000-100%-100000ss-add-debian-12-x86_64-20240206.cgz-ffd294d346d1-20250123-611007-2sqd4l-0.yaml
user=lkp
ARCH=x86_64
kconfig=x86_64-rhel-9.4
commit=ffd294d346d185b70e28b1a28abe367bbfe53c04
intremap=posted_msi
max_uptime=2100
LKP_SERVER=internal-lkp-server
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
	export bm_initrd='/osimage/deps/debian-12-x86_64-20240206.cgz/lkp_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/rsync-rootfs_20241102.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/run-ipconfig_20241102.cgz,/osimage/pkg/debian-12-x86_64-20240206.cgz/ftq-x86_64-0833481-1_20241103.cgz,/osimage/deps/debian-12-x86_64-20240206.cgz/hw_20241102.cgz'
	export ucode_initrd='/osimage/ucode/intel-ucode-20230906.cgz'
	export lkp_initrd='/osimage/user/lkp/lkp-x86_64.cgz'
	export site='inn'
	export LKP_CGI_PORT=80
	export LKP_CIFS_PORT=139
	export job_initrd='/lkp/jobs/scheduled/lkp-ivb-d04/ftq-performance-10000-100%-100000ss-add-debian-12-x86_64-20240206.cgz-ffd294d346d1-20250123-611007-2sqd4l-0.cgz'

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

	run_monitor $LKP_SRC/monitors/wrapper oom-killer
	run_monitor $LKP_SRC/monitors/plain/watchdog

	run_test test='add' freq=10000 $LKP_SRC/bin/run-test ftq
}


extract_stats()
{
	export stats_part_begin=
	export stats_part_end=

	env test='add' freq=10000 $LKP_SRC/stats/wrapper ftq

	$LKP_SRC/stats/wrapper time ftq.time
	$LKP_SRC/stats/wrapper dmesg
	$LKP_SRC/stats/wrapper kmsg
	$LKP_SRC/stats/wrapper last_state
	$LKP_SRC/stats/wrapper stderr
	$LKP_SRC/stats/wrapper time
}


"$@"