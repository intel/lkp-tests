#!/bin/bash

. $LKP_SRC/lib/install.sh
. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/env.sh

fixup_kdir()
{
	# link /lib/modulers/`uname -r`/build to linux_headers_dir
	local linux_headers_dir=$(ls -d /usr/src/linux-headers*-bpf)
	[ -z "$linux_headers_dir" ] && return

	kdir="/lib/modules/$(uname -r)/build"
	ln -svf "$linux_headers_dir" "$kdir"
}

build_module()
{
	local mdir=$1

	local benchmark_path=$(get_benchmark_path)

	log_cmd make -j${nr_cpu} -C $kdir M=$benchmark_path/$mdir 2>&1

	cp $benchmark_path/$mdir/*.ko $benchmark_path/testcases/bin/
}

is_excluded()
{
	test=$1
	local exclude_file=$(get_pkg_dir ltp)/addon/exclude
	cp $exclude_file ./exclude

	# regex match
	for regex in $(cat "$exclude_file" | grep -v '^#' | grep -w ^${test}:.*:regex$ | awk -F: 'NF == 3 {print $2}')
	do
		echo "# regex: $regex generated" >> ./exclude
		cat runtest/$test | awk '{print $1}' | grep -G "$regex" | awk -v prefix=$test":" '$0=prefix$0' >> ./exclude
	done

	orig_test=$(echo "$test" | sed 's/-[0-9]\{2\}$//')
	for i in $(cat ./exclude | grep -v '^#' | grep -w ^$orig_test | awk -F: 'NF == 2')
	do
		ignore=$(echo $i | awk -F: '{print $2}')
		grep -q "^${ignore}" runtest/${test} || continue
		sed -i "s/^${ignore} /#${ignore} /g" runtest/${test}
		echo "<<<test_start>>>"
		echo "tag=${ignore}"
		echo "${ignore} 0 exclude"
		echo "<<<test_end>>>"
	done
}

fixup_env()
{
	# install mkisofs which is linked to genisoimage
	has_cmd mkisofs || {
		genisoimage=$(cmd_path genisoimage)
		if [ -n "$genisoimage" ]; then
			log_cmd ln -sf "$genisoimage" /usr/bin/mkisofs
		else
			echo "can not install mkisofs"
		fi
	}

	set_iptables_path
}

specify_tmpdir()
{
	[ -z "$partitions" ] && return 1
	ltp_partition="${partitions%% *}"
	mount_point=/fs/$(basename $ltp_partition)

	mkdir -p $mount_point/tmpdir || return 1
	tmpdir_opt="-d $mount_point/tmpdir"

	return 0
}

create_single_test_file()
{
	local test=$1

	# hugetlb/hugeshmget02
	echo "$test" | grep -qE ".+/.+" && {
		local group=${test%%/*} # hugetlb
		local sub_test=${test##*/} # hugeshmget02
		grep -E "^$sub_test " "$BENCHMARK_ROOT/ltp/runtest/$group" > $BENCHMARK_ROOT/ltp/runtest/temp_single_test # hugeshmget02 hugeshmget02 -i 10
	}
}

fixup_test()
{
	# group test: syscalls-05
	# single test of a group: syscalls-05/ioprio_set03
	local test=${1%%/*}

	case "$test" in
	cpuhotplug)
		mkdir -p /usr/src/linux/
		;;
	commands)
		fixup_kdir && {
			build_module "testcases/commands/insmod"
			build_module "testcases/commands/lsmod"
		}
		;;
	kernel_misc)
		fixup_kdir && {
			build_module "testcases/kernel/device-drivers/acpi"
			build_module "testcases/kernel/device-drivers/block/block_dev_kernel"
			build_module "testcases/kernel/device-drivers/pci/tpci_kernel"
			build_module "testcases/kernel/device-drivers/tbio/tbio_kernel"
			build_module "testcases/kernel/device-drivers/uaccess"
			build_module "testcases/kernel/firmware/fw_load_kernel"
		}
		;;
	fs_readonly-0*)
		[ -z "$fs" ] && exit
		[ -z "$partitions" ] && exit
		big_dev="${partitions%% *}"
		umount $big_dev
		big_dev_opt="-Z $fs -z $big_dev"
		;;
	fs_ext4)
		[ -z "$partitions" ] && exit
		big_dev="${partitions%% *}"
		big_dev_opt="-z $big_dev"
		# match logic of is_excluded
		sed -i "s/\t/ /g" runtest/fs_ext4
		;;
	lvm.local-*)
		export LTPROOT=${PWD}
		export PATH="$PATH:$LTPROOT/testcases/bin"
		# Creates runtest/lvm.local with testcases for all locally supported FS types
		log_cmd testcases/bin/generate_lvm_runfile.sh
		# Creates 2 LVM volume groups and mounts logical volumes for all locally supported FS types
		log_cmd testcases/bin/prepare_lvm.sh

		# split test to avoid soft_timeout
		cd runtest
		$LKP_SRC/tools/split-tests lvm.local 2 lvm.local-
		cd -
		;;
	mm-oom|mm-min_free_kbytes)
		local pid_job="$(cat $TMP/run-job.pid)"
		echo 0 > /proc/$pid_job/oom_score_adj
		;;
	mm-00)
		[ -z "$partitions" ] && exit
		swap_partition="${partitions%% *}"
		mkswap $swap_partition 2>&1 || exit 1
		swapon $swap_partition
		;;
	tpm_tools)
		[ $USER ] || USER=root
		rm -rf /var/lib/opencryptoki/tpm/$USER
		cd tpm-emulater
		find . -maxdepth 1 -type d -name "TPM_Emulator*" -exec rm -rf {} \;
		unzip $(ls TPM_Emulator*.zip | head -1)
		rsync -av $(ls -l . | awk '/^d/ {print $NF}' | head -1)"/" /
		cd ..
		killall tpmd > /dev/null 2>&1
		tpmd -f -d clear > /dev/null 2>&1 &
		killall tcsd > /dev/null 2>&1
		tcsd -e -f > /dev/null 2>&1 &
		sleep 5
		export LTPROOT=${PWD}
		export LTPBIN=$LTPROOT/testcases/bin
		export OWN_PWD="HELLO1"
		export NEW_OWN_PWD="HELLO2"
		export SRK_PWD="HELLO3"
		export NEW_SRK_PWD="HELLO4"
		export P11_SO_PWD="HELLO5"
		export NEW_P11_SO_PWD="HELLO6"
		export P11_USER_PWD="HELLO7"
		export NEW_P11_USER_PWD="HELLO8"
		;;
	ltp-aiodio.part[24]*|dio-0*|io)
		specify_tmpdir || exit
		;;
	syscalls-ipc-msgstress)
		# avoid soft_timeout by reducing the max number of message
		# queues to 10000(default is 32000)
		echo 10000 > /proc/sys/kernel/msgmni
		;;
	syscalls-0*)
		export LTP_TIMEOUT_MUL=5
		specify_tmpdir || exit

		relatime=$(mount | grep /tmp | grep relatime)
		noatime=$(mount | grep /tmp | grep noatime)
		if [ "$relatime" != "" ] || [ "$noatime" != "" ]; then
			mount -o remount,strictatime /tmp
		fi

		echo "#\$SystemLogSocketName /run/systemd/journal/syslog" > /etc/rsyslog.d/listen.conf
		systemctl restart rsyslog || exit
		[ -f /var/log/maillog ] || {
			touch /var/log/maillog && chmod 600 /var/log/maillog
		}
		[ -e /dev/log ] && rm /dev/log
		ln -s /run/systemd/journal/dev-log /dev/log

		fixup_kdir && {
			# rebuild dummy_del_mod*.ko
			build_module "testcases/kernel/syscalls/delete_module"
			build_module "testcases/kernel/syscalls/finit_module"
			build_module "testcases/kernel/syscalls/init_module"
		}
		;;
	net.ipv6_lib)
		iface=$(ifconfig -s | awk '{print $1}' | grep ^eth | head -1)
		[ -n "$iface" ] && export LHOST_IFACES=$iface
		sed -i "1s/^/::1 ${HOSTNAME}\n/" /etc/hosts
		sed -i "1s/^/127.0.0.1 ${HOSTNAME}\n/" /etc/hosts
		;;
	net.rpc_tests)
		systemctl start openbsd-inetd || exit
		;;
	net_stress.appl-0*)
		[ -d /srv/ftp ] && export FTP_DOWNLOAD_DIR=/srv/ftp
		sed -i '/\/usr\/sbin\/named {/a\\/tmp\/** rw,' /etc/apparmor.d/usr.sbin.named || exit
		systemctl start bind9 || exit
		systemctl list-units | grep -wq apparmor.service && (systemctl reload-or-restart apparmor || exit)
		;;
	scsi_debug.part1-*)
		# fix 'Unable to make dir /test/growfiles/XXX' error
		mkdir -p /test/growfiles
		;;
	tracing)
		export LTP_TIMEOUT_MUL=5
		;;
	esac
}

cleanup_ltp()
{
	# group test: syscalls-05
	# single test of a group: syscalls-05/ioprio_set03
	local test=${1%%/*}

	case "$test" in
	lvm.local-*)
		export LTPROOT=${PWD}
		export PATH="$PATH:$LTPROOT/testcases/bin"
		# remove LVM volume groups created by prepare_lvm.sh and release the associated loop devices
		log_cmd testcases/bin/cleanup_lvm.sh
		;;
	mm-oom|mm-min_free_kbytes)
		dmesg -C
		;;
	syscalls-0*)
		[ "$relatime" != "" ] && mount -o remount,relatime,user_xattr /tmp
		[ "$noatime" != "" ] && mount -o remount,noatime,user_xattr /tmp
		;;
	esac
}
