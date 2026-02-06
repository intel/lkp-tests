#!/bin/sh
. $LKP_SRC/lib/job-init.sh

# clear the initrds exported by last job
unset_last_initrd_vars()
{
	for last_initrd in $(env | grep "initrd=" | awk -F'=' '{print $1}')
	do
		unset $last_initrd
	done
}

read_kernel_cmdline_vars_from_append()
{
	unset_last_initrd_vars

	for i in $1
	do
		# shellcheck disable=SC2163
		{
		[ "$i" != "${i#job=}" ]			&& export "$i"
		[ "$i" != "${i#RESULT_ROOT=}" ]		&& export "$i"
		[ "$i" != "${i#initrd=}" ]		&& export "$i"
		[ "$i" != "${i#bm_initrd=}" ]		&& export "$i"
		[ "$i" != "${i#job_initrd=}" ]		&& export "$i"
		[ "$i" != "${i#lkp_initrd=}" ]		&& export "$i"
		[ "$i" != "${i#modules_initrd=}" ]	&& export "$i"
		[ "$i" != "${i#testing_nvdimm_modules_initrd=}" ]      && export "$i"
		[ "$i" != "${i#tbox_initrd=}" ]		&& export "$i"
		[ "$i" != "${i#linux_headers_initrd=}" ]	&& export "$i"
		[ "$i" != "${i#linux_selftests_initrd=}" ]	&& export "$i"
		[ "$i" != "${i#linux_perf_initrd=}" ]	&& export "$i"
		[ "$i" != "${i#ucode_initrd=}" ]   && export "$i"
		}
	done
}

download_kernel()
{
	kernel="$(echo $kernel | sed 's/^\///')"

	echo "downloading kernel image $kernel ..."
	set_job_state "wget_kernel"

	kernel_file=$CACHE_DIR/$kernel
	http_get_newer "$kernel" $kernel_file || {
		set_job_state "wget_kernel_fail"
		echo "failed to download kernel: $kernel" 1>&2
		return 1
	}
}

# if no rootfs_partition, mark it as modified
# FIXME: hard code isn't a good choice
is_local_cache()
{
	[ "$CACHE_DIR" = "/opt/rootfs/tmp" ]
}

initrd_is_modified()
{
	local file=$1
	local md5sumfile=$file.md5sum
	local new_md5sum

	is_local_cache || return 0

	new_md5sum="$(md5sum $file)"

	[ -f $md5sumfile ] || return 0
	[ -n "$new_md5sum" ] && [ "$(cat $md5sumfile)" = "$new_md5sum" ] && {
		echo "$file isn't modified"
		return 1
	}

	return 0
}

initrd_is_correct()
{
	local file=$1

	initrd_is_modified $file || return 0
	gzip -dc $file | cpio -t >/dev/null
	ret=$?

	# update md5sum only when it's correct
	[ $ret -eq 0 ] && is_local_cache && md5sum $file >$file.md5sum

	return $ret
}

# for lkp qemu, it will set LKP_LOCAL_RUN=1
use_local_modules_initrds()
{
	[ "$LKP_LOCAL_RUN" = "1" ] && [ "$modules_initrd" ] && {
		# lkp qemu will create a link to modules.cgz under $CACHE_DIR
		# ls -al /root/.lkp/cache/modules.cgz
		# lrwxrwxrwx 1 root root 21 Jun 19 08:13 /root/.lkp/cache/modules.cgz -> /lkp-qemu/modules.cgz
		local local_modules="$CACHE_DIR/$(basename "$modules_initrd")"
		[ -e $local_modules ] || return
		echo "use local modules: $local_modules"
		unset modules_initrd
		local_modules_initrd=$local_modules
	}
}

# shellcheck disable=SC2120
download_initrd()
{
	local _initrd=
	local initrds=
	local local_modules_initrd=

	echo "downloading initrds ..."
	set_job_state "wget_initrd"

	use_local_modules_initrds

	for _initrd in $(echo $initrd $tbox_initrd $job_initrd $lkp_initrd $bm_initrd $keep_initrds $modules_initrd $testing_nvdimm_modules_initrd $linux_headers_initrd $linux_selftests_initrd $linux_perf_initrd $ucode_initrd | tr , ' ')
	do
		local file
		_download_initrd $_initrd || return

		initrds="${initrds}$file "
	done

	# modules can not be the first, must be behind initrd
	initrds="${initrds} $local_modules_initrd"

	[ -n "$initrds" ] && {
		[ $# != 0 ] && initrds="${initrds}$*"

		concatenate_initrd="$CACHE_DIR/initrd-concatenated"
		initrd_option="--initrd=$concatenate_initrd"

		cat $initrds > $concatenate_initrd
	}

	return 0
}

_download_initrd()
{
	local initrd=$1
	initrd=$(echo $initrd | sed 's/^\///')

	file=$CACHE_DIR/$initrd
	if [ "$LKP_LOCAL_RUN" = "1" ] && [ -e $file ]; then
		echo "skip downloading $file"
	else
		http_get_newer "$initrd" $file || {
			rm -f $file
			set_job_state "wget_initrd_fail"
			echo Failed to download $initrd
			return 1
		}
	fi

	initrd_is_correct $file || {
		rm -f $file && echo "remove the the broken initrd: $file"

		set_job_state "initrd_broken"
		echo_info "WARNING: lkp next download broken!"

		return 1
	}

	return 0
}

detect_acpi_rsdp_mismatch()
{
	local append="$1"
	local acpi_rsdp="$2"

	local job_acpi_rsdp="$(echo "$append" | grep -o -E "acpi_rsdp=0x[0-9a-fA-F]+" | cut -d= -f2)"
	[ -n "$job_acpi_rsdp" ] || echo "acpi_rsdp is not set in bootloader_append param of the next job"

	[ -n "$job_acpi_rsdp" ] && [ -n "$acpi_rsdp" ] && [ "$job_acpi_rsdp" != "$acpi_rsdp" ] && {
		set_job_state "acpi_rsdp_mismatch_deteced"
		echo "acpi_rsdp_mismatch_deteced, $job_acpi_rsdp != $acpi_rsdp" 1>&2
	}
}

get_acpi_rsdp_from_dmesg()
{
	local dmesg_source="$1"
	local dmesg_acpi_rsdp

	[ -n "$dmesg_source" ] || return

	if [ "$dmesg_source" = "dmesg" ]; then
		dmesg_acpi_rsdp=$(dmesg | grep -m1 "ACPI: RSDP")
	elif [ -f "$dmesg_source" ]; then
		dmesg_acpi_rsdp=$(grep -m1 "ACPI: RSDP" "$dmesg_source")
	else
		echo "invalid dmesg source"
		return 1
	fi

	if [ -n "$dmesg_acpi_rsdp" ]; then
		# get the last 8 digits, convert to lowercase
		acpi_rsdp="0x$(echo "$dmesg_acpi_rsdp" | grep -o -E "0x[0-9a-fA-F]+" | cut -c 11- | tr '[:upper:]' '[:lower:]')"
	else
		echo "no acpi_rsdp from dmesg"
	fi
}

echo_info()
{
	echo "$@"
	echo "$@" > /dev/ttyS0 &
}

kexec_to_next_job()
{
	local kernel append acpi_rsdp download_errno
	kernel=$(awk  '/^KERNEL / { print $2; exit }' $NEXT_JOB)
	append=$(grep -m1 '^APPEND ' $NEXT_JOB | sed 's/^APPEND //')
	rm -f /tmp/initrd-* /tmp/modules.cgz

	read_kernel_cmdline_vars_from_append "$append"
	append=$(echo "$append" | sed -r 's/ [a-z_]*initrd=[^ ]+//g')

	# Pass the RSDP address to the kernel for EFI system
	# Root System Description Pointer (RSDP) is a data structure used in the
	# ACPI programming interface. On systems using Extensible Firmware
	# Interface (EFI), attempting to boot a second kernel using kexec, an ACPI
	# BIOS Error (bug): A valid RSDP was not found (20160422/tbxfroot-243) was
	# logged.

	# if efi is enabled, read ACPI from efi systab
	# it may have multiple versions such as ACPI, ACPI 2.0, and maybe ACPI 3.0 coming in the future
	# the newest version will be put on top, so we always read the first line
	# $ cat Documentation/ABI/testing/sysfs-firmware-efi
	# What:           /sys/firmware/efi/systab
	# Date:           April 2005
	# Contact:        linux-efi@vger.kernel.org
	# Description:    Displays the physical addresses of all EFI Configuration
	#                 Tables found via the EFI System Table. The order in
	#                 which the tables are printed forms an ABI and newer
	#                 versions are always printed first, i.e. ACPI20 comes
	#                 before ACPI.
	# Users:          dmidecode
	# $ cat /sys/firmware/efi/systab
	# ACPI20=0x36937000
	# ACPI=0x36937000
	# SMBIOS3=0x384cf000
	# SMBIOS=0x384d0000
	acpi_rsdp=$(grep -m1 ^ACPI /sys/firmware/efi/systab 2>/dev/null | cut -f2- -d=)

	# if efi is disabled, read acpi_rsdp from dmesg log
	# if dmesg has "ACPI: RSDP 0x0000...", it must be a correct value of a successful boot
	# if dmesg has "ACPI:      0x0000..." (missing RSDP keyword), it means the value is a wrong one
	# [    0.008415] ACPI: RSDP 0x0000000036937000 000024 (v02 ALASKA)
	# [    1.212964] ACPI: RSDP 0x00000000699FD014 000024 (v02 INTEL )
	[ -n "$acpi_rsdp" ] || get_acpi_rsdp_from_dmesg "dmesg"

	detect_acpi_rsdp_mismatch "$append" "$acpi_rsdp"

	if [ -n "$acpi_rsdp" ]; then
		# append correct acpi_rsdp value as the last param, so it can overwrite previous one if job yaml provides a wrong value
		append="$append acpi_rsdp=$acpi_rsdp"
	else
		# acpi_rsdp is not found in either efi systab or dmesg
		# this should be an abnormal case
		echo "cannot get acpi_rsdp from efi systab or dmesg" 1>&2
	fi

	jobfile_append_var "last_kernel=$(uname -r)"
	jobfile_append_var "acpi_rsdp=$acpi_rsdp"

	download_kernel
	download_errno=$?

	[ $download_errno -eq 0 ] && {
		keep_initrds='' download_initrd
		download_errno=$?
	}

	echo_info "LKP: kexec loading ... acpi_rsdp: $acpi_rsdp"
	echo kexec --noefi -l $kernel_file $initrd_option
	sleep 1 # kern  :warn  : [  +0.000073] sed: 34 output lines suppressed due to ratelimiting
	echo --append="${append}"
	sleep 1

	dmesg --human --decode --color=always | gzip > /tmp/pre-dmesg.gz
	if [ -d "/$LKP_SERVER/$RESULT_ROOT/" ]; then
		mv /tmp/pre-dmesg.gz "/$LKP_SERVER/$RESULT_ROOT/pre-dmesg.gz"
		chown lkp.lkp "/$LKP_SERVER/$RESULT_ROOT/pre-dmesg.gz" && sync
	elif supports_raw_upload; then
		JOB_RESULT_ROOT=$RESULT_ROOT
		upload_files /tmp/pre-dmesg.gz
	fi

	# store dmesg to disk and reboot
	[ $download_errno -ne 0 ] && {
		echo_info "LKP: rebooting ... $download_errno"
		sleep 119 && reboot
		exit
	}

	set_job_state "booting"

	kexec --noefi -l $kernel_file $initrd_option --append="$append"

	if [ -n "$(find /etc/rc6.d -name '[SK][0-9][0-9]kexec' 2>/dev/null)" ]; then
		# expecting the system to run "kexec -e" in some rc6.d/* script
		echo_info "LKP: rebooting by exec"
		kexec -e 2>/dev/null
		sleep 100 || exit	# exit if reboot kills sleep as expected
	fi

	# run "kexec -e" manually. This is not a clean reboot and may lose data,
	# so run umount and sync first to reduce the risks.
	umount -a
	sync
	echo_info "LKP: kexecing"
	kexec -e 2>/dev/null

	set_job_state "kexec_fail_from_job"
	echo_info "WARNING: lkp next kexec fail!"

	# in case kexec failed
	echo_info "LKP: rebooting after kexec"
	reboot 2>/dev/null
	sleep 244 || exit
	echo s > /proc/sysrq-trigger
	echo b > /proc/sysrq-trigger
}
