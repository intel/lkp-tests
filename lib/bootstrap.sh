#!/bin/sh

. $LKP_SRC/lib/detect-system.sh
. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/http.sh
. $LKP_SRC/lib/kexec.sh
. $LKP_SRC/lib/mount.sh
. $LKP_SRC/lib/network.sh
. $LKP_SRC/lib/reboot.sh
. $LKP_SRC/lib/tbox.sh
. $LKP_SRC/lib/ucode.sh

# borrowed from linux/tools/testing/selftests/rcutorture/doc/initrd.txt
# Author: Paul E. McKenney <paulmck@linux.vnet.ibm.com>
mount_dev()
{
	[ -d /dev/pts ] &&
	[ -c /dev/kmsg ] &&
	[ -c /dev/null ] &&
	[ -c /dev/ttyS0 ] &&
	[ -c /dev/console ] && return

	mkdir -p /dev &&
	mount -t devtmpfs -o mode=0755 udev /dev &&
	mkdir -p /dev/pts &&
	mount -t devpts -o noexec,nosuid,gid=5,mode=0620 devpts /dev/pts && return

	has_cmd mknod || return

	echo "W: devtmpfs not available, falling back to tmpfs for /dev"
	mount -t tmpfs -o mode=0755 udev /dev

	[ -e /dev/console ]	|| mknod -m 600 /dev/console c 5 1
	[ -e /dev/kmsg ]	|| mknod -m 644 /dev/kmsg c 1 11
	[ -e /dev/null ]	|| mknod -m 666 /dev/null c 1 3
}

mount_kernel_fs()
{
	[ -d /proc/1 ] ||
	mount -t proc -o noexec,nosuid,nodev proc /proc

	[ -d /sys/kernel ] ||
	mount -t sysfs -o noexec,nosuid,nodev sysfs /sys

	mount_dev
}

mount_tmpfs()
{
	# ubuntu etc/init/mounted-tmp.conf wrongly mounted /tmp:
	# mount -t tmpfs -o size=1048576,mode=1777 overflow /tmp
	# grep -q /tmp /proc/mounts && umount /tmp

	is_mount_point /tmp && return

	mount -t tmpfs -o mode=1777 tmp /tmp
}

# Many randconfig test kernels may not have the necessary NIC driver.
# Show warning only when the kernel does compile in suitable driver.
# QEMU VMs use e1000 or virtio; HW machines mostly have e1000 or igb.
# Let's catch and warn the common case.
warn_no_eth0()
{
	[ -f /proc/config.gz ] || return

	zcat /proc/config.gz | grep -q -F -x -e 'CONFIG_E1000=y' -e 'CONFIG_E1000E=y' || return

	echo "!!! IP-Config: No eth0/1/.. under /sys/class/net/ !!!" >&2
}

setup_network()
{
	network_ok && return || { echo "LKP: waiting for network..."; sleep 2; }
	network_ok && return || sleep 5
	network_ok && return || sleep 10
	network_ok && return

	is_virt &&
	[ ! -e /usr/share/initramfs-tools/scripts/functions ] && {
		export NO_NETWORK=1
		echo "export NO_NETWORK=1 due to no initramfs-tools"
		return
	}

	local net_devices=$(get_net_devices)
	if [ -z "$net_devices" ]; then

		warn_no_eth0

		echo \
		ls /sys/class/net
		ls /sys/class/net

		# VMs do many randconfig boot tests which can write the
		# valuable dmesg/kmsg to ttyS0/ttyS1
		if is_virt; then
			export NO_NETWORK=1
			echo "export NO_NETWORK=1 due to no net devices"
			return
		else
			reboot 2>/dev/null
			exit
		fi
	fi

	$LKP_DEBUG_PREFIX $LKP_SRC/bin/run-ipconfig
	network_ok && return

	# final try by directly calling "net_devices_link" then dhclient
	net_devices_link up
	sleep 60 # 'up' could be not so fast
	dhclient
	network_ok && return

	local err_msg='IP-Config: Auto-configuration of network failed'
	dmesg | grep -q -F "$err_msg" || {
		# Include $err_msg in the error message so that it matches
		# /lkp/lkp/printk-error-messages
		# and be detected as a dmesg error. Add some prefix/sufix
		# to slightly distinguish it from kernel DHCP failure message.
		echo "!!! $err_msg !!!" >&2
		echo "!!! $err_msg !!!" > /dev/ttyS0
	}

	if is_virt; then
		export NO_NETWORK=1
		echo "export NO_NETWORK=1 due to config network failed"
		return
	else
		reboot 2>/dev/null
		exit
	fi
}

add_lkp_user()
{
	if has_cmd getent; then
		getent passwd lkp >/dev/null && return
	else
		grep -q '^lkp:' /etc/passwd && return
	fi

	mkdir -p /home

	if has_cmd useradd; then
		groupadd --gid 1090 lkp
		useradd --uid 1090 --gid 1090 lkp
	elif has_cmd adduser; then
		# busybox applet
		# quiet this F_SETLK error in yocto tiny image:
		# adduser: warning: can't lock '/etc/passwd': Permission denied
		adduser -D -u 1090 lkp 2>/dev/null
	else
		echo 'lkp:x:1090:1090::/home/lkp:/bin/sh' >> /etc/passwd
		echo 'lkp:x:1090:' >> /etc/group
	fi
}

run_ntpdate()
{
	[ -z "$NO_NETWORK" ] || return

	[ "$LKP_SERVER" = internal-lkp-server ] || return

	[ -x '/usr/sbin/ntpdate' ] || return

	local hour="$(date +%H)"

	ntpdate -b $LKP_SERVER

	[ "$hour" != "$(date +%H)" ] && [ -x '/etc/init.d/hwclock.sh' ] && {
		# update hardware clock, to carry the adjusted time across reboots
		/etc/init.d/hwclock.sh restart 2> /dev/null
	}
}

setup_hostname()
{
	export HOSTNAME=${testbox:-localhost}

	echo $HOSTNAME > /tmp/hostname
	ln -fs /tmp/hostname /etc/hostname

	if has_cmd hostname; then
		hostname $HOSTNAME
	else
		echo $HOSTNAME > /proc/sys/kernel/hostname
	fi
}

setup_hosts()
{
	# /etc/hosts may be shared when it's NFSROOT and there is no obvious
	# way to detect if rootfs is already RAM based. So unconditionally
	# symlink it to my own tmpfs copy.
	local tmpfs_hosts=/tmp/my_hosts

	if [ -f '/etc/hosts-orig' ]; then
		cp /etc/hosts-orig $tmpfs_hosts
	else
		cp /etc/hosts $tmpfs_hosts
	fi
	echo "127.0.0.1 $HOSTNAME.sh.intel.com  $HOSTNAME" >> $tmpfs_hosts
	echo "::1 $HOSTNAME.sh.intel.com  $HOSTNAME" >> $tmpfs_hosts
	ln -fs $tmpfs_hosts /etc/hosts
}

show_mac_addr()
{
	if has_cmd ip; then
		ip link | awk '/ether/ {print $2; exit}'
	else
		ifconfig 2>/dev/null | awk '/ether/ {print $2; exit}'
	fi
}

echo_to_tty()
{
	echo "LKP: stdout: $$: $@"

	for ttys in ttyS0 ttyS1 ttyS2 ttyS3
	do
		echo "LKP: $ttys: $$: $@" > /dev/$ttys 2>/dev/null
	done
}

announce_bootup()
{
	local version="$(cat /proc/sys/kernel/version 2>/dev/null| cut -f1 -d' ' | cut -c2-)"
	local release="$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
	local mac="$(show_mac_addr)"

	echo_to_tty 'Kernel tests: Boot OK!'

	# make sure to output something if serial console is not ttyS0
	# this helps diagnose serial console connections
	echo_to_tty "HOSTNAME $HOSTNAME, MAC $mac, kernel $release $version"
}

redirect_stdout_stderr_directly()
{
	echo "redirect stdout and stderr directly"

	tail -f /tmp/stdout > /dev/kmsg 2>/dev/null &
	echo $! >> /tmp/pid-tail-global
	tail -f /tmp/stderr > /dev/kmsg 2>/dev/null &
	echo $! >> /tmp/pid-tail-global
}

redirect_stdout_stderr()
{
	[ -c /dev/kmsg ] || {
		echo_to_tty "/dev/kmsg doesn't exist"
		return 1
	}

	has_cmd tail || {
		echo_to_tty "tail cmd doesn't exist"
		return 1
	}

	exec  > /tmp/stdout
	exec 2> /tmp/stderr

	[ "$no_redirect_to_kmsg" = "1" ] && return

	local sed_u=
	sed -h 2>&1|grep -q -- -u && sed_u='-u'

	local stdbuf='stdbuf -o0 -e0'
	has_cmd stdbuf || stdbuf=

	if uname -m | grep -q riscv64; then
		# do not use stdbuf or sed -u to avoid unnecessary buffering on ricsv64 distro
		redirect_stdout_stderr_directly
	elif [ -n "$stdbuf$sed_u" ]; then
		# limit 300 characters is to fix the following errro info:
		# sed: couldn't write N items to stdout: Invalid argument
		tail -f /tmp/stdout | $stdbuf sed $sed_u -r 's/^(.{0,900}).*$/<5>\1/' > /dev/kmsg &
		echo $! >> /tmp/pid-tail-global
		tail -f /tmp/stderr | $stdbuf sed $sed_u -r 's/^(.{0,900}).*$/<3>\1/' > /dev/kmsg &
		echo $! >> /tmp/pid-tail-global
	else
		redirect_stdout_stderr_directly
	fi
}

install_initrd()
{
	[ -n "$keep_initrds" ] || return 0

	local keep_initrd_dir="$CACHE_DIR/keep-initrd"

	rm -rf $keep_initrd_dir
	mkdir $keep_initrd_dir

	local initrd
	for initrd in $(echo $keep_initrds | tr , ' ')
	do
		local file
		_download_initrd $initrd || return

		echo "gzip -dc $file | cpio -dimu"
		(cd $keep_initrd_dir && gzip -dc $file | cpio -dimu)
	done

	mkdir -vp /lkp/benchmarks

	local dir
	for dir in $keep_initrd_dir/lkp/benchmarks/*/
	do
		[ -d "$dir" ] || continue

		dir="${dir%/}"
		# rli9 FIXME /lkp/benchmarks/$(basename $dir) could exist
		ln -svf $dir /lkp/benchmarks/$(basename $dir)
	done

	return 0
}

install_deb()
{
	local files
	local filename
	local filter_info="dpkg: warning: files list file for package '.*' missing;"

	[ -d /opt/deb ] || return 0

	# round one, install all debs directly
	files="$(find /opt/deb -name '*.deb' -type f 2>/dev/null)"
	[ -n "$files" ] || return

	# fix the issue when install mysql
	# ERROR: There's not enough space in /var/lib/mysql/
	echo $files | grep -q "mysql" && {
		mkdir -p /tmp/lib/mysql /var/lib/mysql
		mount --bind /tmp/lib/mysql /var/lib/mysql
	}

	# pack-deps have packed all depencecy packages into /osimage/deps/xxx/benchmark.cgz,
	# but it does not update dpkg database which will make dpkg misunderstand we have not
	# solved the dependent relationship, so here we ignore the dependency errors
	echo "install debs round one: dpkg -i --force-confdef --force-depends $files"
	dpkg -i --force-confdef --force-depends $files 2>/tmp/dpkg_error && return
	grep -v "$filter_info" /tmp/dpkg_error

	# round two, install all debs one by one accroding to keep-deb which is in sequence
	# sort keep-deb.${benchmark} by time, handle the oldest keep-deb.${benchmark} first
	# shellcheck disable=SC2045
	for keepfile in $(ls -rt /opt/deb/keep-deb*)
	do
		echo "handle $keepfile..."
		# due to gwak pkg including pre-dependency definition,
		# gawk dependent libreadline7 install first.
		# so we generated keep-deb file which contains installation sequence,
		# and line by line installation.
		while read -r filename
		do
			echo "install debs round two: dpkg -i --force-confdef --force-depends /opt/deb/$filename"
			dpkg -i --force-confdef --force-depends /opt/deb/$filename 2>/tmp/dpkg_error || {
				grep -v "$filter_info" /tmp/dpkg_error
				echo "error: dpkg -i /opt/deb/$filename failed." 1>&2
				return 1
			}
		done < "$keepfile"
	done
}

install_rpms()
{
	[ -d /opt/rpms ] || return

	detect_system

	if [ $_system_name_lowercase = 'centos' ] && [ $_system_version -ge 8 ]; then
		dnf install -y --allowerasing --skip-broken --disablerepo=* /opt/rpms/*.rpm
	else
		rpm -ivh --force --ignoresize /opt/rpms/*.rpm
	fi
}

try_get_and_set_distro()
{
	[ -n "$DISTRO" ] && return

	local rootfs=$(grep "rootfs:" $job | cut -d: -f2 | sed 's/ //g')
	DISTRO=${rootfs%%-*}
	DISTRO=${DISTRO##*/}
}

fixup_packages()
{
	install_deb

	install_rpms

	has_cmd ldconfig &&
	ldconfig

	[ -x /usr/bin/gcc ] && [ ! -e /usr/bin/cc ] &&
	ln -sf gcc /usr/bin/cc

	# hpcc dependent library
	[ -e /usr/lib/atlas-base/atlas/libblas.so.3 ] && [ ! -e /usr/lib/libblas.so.3 ] &&
	ln -sf /usr/lib/atlas-base/atlas/libblas.so.3 /usr/lib/libblas.so.3

	local aclocal_bin
	for aclocal_bin in /usr/bin/aclocal-*
	do
		[ -x "$aclocal_bin" ] && [ ! -e /usr/bin/aclocal ] &&
		ln -sf $aclocal_bin /usr/bin/aclocal
	done

	# /lib64/ld-linux-x86-64.so.2 program interpreter
	[ -e /lib64/ld-linux-x86-64.so.2 ] || {
		[ -d /lib64 ] || mkdir /lib64
		ln -s /lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2
	}
}

mount_debugfs()
{
	check_mount debug /sys/kernel/debug -t debugfs
}

# cache pkg for only one week to avoid "no space left" issue
cleanup_pkg_cache()
{
	local pkg_cache=$1
	local cleanup_stamp=$pkg_cache/cleanup_stamp/$(date +%U)
	[ -d "$cleanup_stamp" ] && return
	mkdir $cleanup_stamp -p

	for delday in $(seq 14 -1 0)
	do
		# df /dev/sda1
		# Filesystem     1K-blocks      Used Available Use% Mounted on
		# /dev/sda1      960380648 316688212 594837976  35% /opt/rootfs
		disk_usage=$(df "$rootfs_partition" | grep "/opt/rootfs" | awk '{print $(NF-1)}' | awk -F'%' '{print $1}')
		[ "$disk_usage" -lt 80 ] && break

		find "$pkg_cache" \( -type f -mtime +${delday} -delete \) -or \( -type d -ctime +${delday} -empty -delete \)
	done
	echo "After clean up pkg cache, $rootfs_partition disk usage is $disk_usage%"
}

wait_load_disk()
{
	# set the max time of wait is 150s
	for i in $(seq 30)
	do
		# eg: /dev/disk/by-id/ata-WDC_WD1002FAEX-00Z3A0_WD-WCATRC577623-part2
		ls $rootfs_partition >/dev/null 2>&1 && return
		# eg: LABEL=LKP-ROOTFS
		blkid | grep -q ${rootfs_partition#*=} && return
		sleep 5
	done

	return 1
}

mount_rootfs_partition()
{
	mkdir -p $ROOTFS_DIR

	modprobe btrfs || {
		echo_to_tty "fail to modprobe btrfs"
	}

	mount $rootfs_partition $ROOTFS_DIR && return

	mkfs.btrfs -f $rootfs_partition || return

	mount $rootfs_partition $ROOTFS_DIR || {
		set_job_state 'mount_rootfs_fail'
		return 1
	}
}

mount_rootfs()
{
	if [ -n "$rootfs_partition" ]; then
		# wait for the machine to load the disk
		wait_load_disk || {
			# skipping following test if disk can't be load
			echo_to_tty "can't load the disk $rootfs_partition, skip testing..."
			set_job_state 'load_disk_fail'
			return 1
		}

		ROOTFS_DIR=/opt/rootfs

		mount_rootfs_partition && {
			CACHE_DIR=$ROOTFS_DIR/tmp
			mkdir -p $CACHE_DIR

			cleanup_pkg_cache $CACHE_DIR
		}
	fi

	[ -n "$CACHE_DIR" ] || CACHE_DIR=/tmp/cache
	mkdir -p $CACHE_DIR

	echo "INFO: lkp CACHE_DIR is $CACHE_DIR"

	export CACHE_DIR
}

show_default_gateway()
{
	if has_cmd ip; then
		ip -4 route list 0/0 | cut -f3 -d' '
	else
		route -n | awk '$4 == "UG" {print $2}'
	fi
}

show_gateway_mac()
{
	if has_cmd ip; then
		ip neigh | grep "$1" | awk '{print $5}'
	else
		arp "$1" | grep "$1" | awk '{print $3}'
	fi
}

show_default_interface()
{
	if has_cmd ip; then
		ip -4 route list 0/0 | cut -f5 -d' '
	else
		route -n | awk '$4 == "UG" {print $8}'
	fi
}

netconsole_init()
{
	# don't init netconsole at local run
	[ "$LKP_LOCAL_RUN" = "1" ] && return

	[ -z "$netconsole_port" ] && return
	[ -n "$NO_NETWORK" ] && return

	# use default gateway as netconsole server
	netconsole_server=$(show_default_gateway)
	# Select the interface that can access netconsole server
	netconsole_interface=$(show_default_interface)
	[ -n "$netconsole_server" ] || return
	netconsole_server_mac=$(show_gateway_mac "$netconsole_server")
	# eth0 is default interface if netconsole_interface is null.
	modprobe netconsole netconsole=@/$netconsole_interface,$netconsole_port@$netconsole_server/$netconsole_server_mac
}

download_job()
{
	last_job=$job
	# the downloaded $NEXT_JOB could be wrong to be binary file, which leads to below error
	# grep: /tmp/next-job-lkp: binary file matches
	job="$(grep -o 'job=[^ ]*.yaml' $NEXT_JOB | awk -F 'job=' '{print $2}')"
	[ -n "$job" ] || {
		echo "WARNING: lkp next download broken!"
		return 1
	}

	local job_cgz=${job%.yaml}.cgz
	# TODO: escape is necessary. We might also need download some extra cgz
	http_get_file "$job_cgz" /tmp/next-job.cgz
	(cd /; gzip -dc /tmp/next-job.cgz | cpio -id)
}

__reboot_bad_next_job()
{
	set_tbox_wtmp 'rebooting_bad_next_job'
	sleep 1
	reboot_tbox 2>/dev/null && exit
}

next_job()
{
	LKP_USER=${pxe_user:-lkp}

	__next_job || {
		[ "$LKP_USER" != "lkp" ] && __reboot_bad_next_job

		local secs=300
		while true; do
			sleep $secs || exit # killed by reboot
			secs=$(( secs + 300 ))
			__next_job && break
		done
	}

	download_job
}

rsync_rootfs()
{
	[ -n "$VM_VIRTFS" ] && return
	[ -n "$NO_NETWORK" ] && return
	[ -z "$LKP_SERVER" ] && return

	local append="$(grep -m1 '^APPEND ' $NEXT_JOB | sed 's/^APPEND //')"
	for i in $append
	do
		[ "$i" != "${i#remote_rootfs=}" ] && export "$i"
		[ "$i" != "${i#root=}" ] && export "$i"
	done

	if [ -n "$remote_rootfs" -a -n "$root" ]; then
		$LKP_DEBUG_PREFIX $LKP_SRC/bin/rsync-rootfs $remote_rootfs $root

		# reboot only if rsynced rootfs is incomplete
		# What we really need to avoid is INCOMPLETE rsync, which might lead
		# to unexpected consistency problems
		local rootfs_name=${remote_rootfs##*/}
		# To remove the version info from rootfs's name
		# eywa-x86_64-20160714-1 ==> eywa-x86_64
		rootfs_name=${rootfs_name%*-[0-9]*-[0-9]}
		[ -f "$ROOTFS_DIR/$rootfs_name/etc/rsync-rootfs-complete" ] || {
			echo "rsync rootfs incomplete: from $remote_rootfs to $root" >&2
			exit 1
		}
	fi
}

is_same_kernel_and_rootfs()
{
	local next_kernel=$(awk '/^kernel: /{print $2}' $job | tr -d '"')
	[ -n "$next_kernel" ] || {
		echo "ERROR: no kernel in the job file: $job"
		return 1
	}

	if [ "$kernel" = "$next_kernel" ]; then
		# check run_on_local_disk flag in current and next job files
		# if run_on_local_disk setting is different, reboot is required
		grep -q "^run_on_local_disk: [a-zA-Z0-9_]*" $job
		if [ $? -eq 0 ]; then
			[ -n "$run_on_local_disk" ] || return 1
		else
			[ -n "$run_on_local_disk" ] && return 1
		fi

		is_same_cmdline || return 1

		local next_rootfs=$(awk '/^rootfs: /{print $2}' $job)
		[ -n "$next_rootfs" ] || {
			echo "ERROR: no rootfs in the job file: $job"
			return 1
		}

		[ "$rootfs" = "$next_rootfs" ] && return 0
	fi

	return 1
}

is_same_testcase()
{
	local current_testcase=$testcase
	local next_testcase=$(awk '/^testcase: /{print $2}' $job | tr -d '"')

	[ "$current_testcase" = "$next_testcase" ]
}

is_same_bp_memmap()
{
	local next_bp_memmap=$(awk '/bp_memmap:/{print $2}' $job)
	# $ awk -F'memmap=' '{print $2}' /proc/cmdline | awk '{print $1}'
	# 32G!4G
	local current_memmap=$(awk -F'memmap=' '{print $2}' /proc/cmdline | awk '{print $1}')

	[ "$next_bp_memmap" = "$current_memmap" ]
}

is_same_cmdline()
{
	local current_kernel_cmdline=$kernel_cmdline
	local next_kernel_cmdline=$(awk '/kernel_cmdline:/{print $2}' $job)

	[ "$current_kernel_cmdline" = "$next_kernel_cmdline" ]
}

setup_env()
{
	[ "$result_service" != "${result_service#9p/}" ] && {
		export VM_VIRTFS=1
		echo "export VM_VIRTFS=1 due to result service $result_service"
	}
}

add_nfs_default_options()
{
	echo "[ NFSMount_Global_Options ]" >>/etc/nfsmount.conf
	echo "  nolock=True" >>/etc/nfsmount.conf
}

show_kernel_tainted_state()
{
	echo "lkp: kernel tainted state: $(cat /proc/sys/kernel/tainted)"
}

# initiation at boot stage; should be invoked once for
# each fresh boot.
boot_init()
{
	deploy_intel_ucode
	setup_env

	mount_kernel_fs
	mount_tmpfs
	redirect_stdout_stderr

	if is_virt; then
		echo "is_virt=true"
	else
		echo "is_virt=false"
	fi

	show_kernel_tainted_state

	setup_hostname
	setup_hosts

	announce_bootup

	add_lkp_user

	fixup_packages

	setup_network
	echo "NO_NETWORK=$NO_NETWORK"

	run_ntpdate

	mount_debugfs

	if is_aliyunos; then
		add_nfs_default_options
	fi

	netconsole_init

	mount_rootfs

	install_initrd
}
