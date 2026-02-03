#!/bin/bash

cleanup_qemu_drives()
{
	rm -f $VDISK_ROOT/initrd-$vm_name.cgz

	[[ $persistent_storage ]] || {
		rm -f $VDISK_ROOT/disk-$vm_name-[0-9]
		rm -f $VDISK_ROOT/disk-$vm_name-[0-9][0-9]
	}
}

string_to_associative_array()
{
	local map
	local key
	local val
	declare -A -g $2
	for map in ${!1}
	do
		key=${map%%=*}
		val=${map#*=}
		eval "$2[$key]=$val"
	done
}

setup_qemu_drives()
{
	case $disk_type in
	virtio-scsi)
		QEMU_DRIVE_OPTION='-device virtio-scsi-pci,id=scsi0 '
		;;
	*)
		QEMU_DRIVE_OPTION=
		;;
	esac

	(( VDISK_NUM )) || return 0

	QEMU_IMG_SIZES=()

	local i
	local disk_names=(vd{a..z})
	[[ $qemu_img ]] && string_to_associative_array qemu_img array_qemu_img
	for ((i = 0; i < VDISK_NUM; i++))
	do
		local disk=$VDISK_ROOT/disk-$vm_name-$i
		local size=256G

		[[ $qemu_img ]] && {
			local qemu_img_option="${array_qemu_img[${disk_names[$i]}]}"
			[[ $qemu_img_option =~ ^([0-9]+[MGT])$ ]]	&& size=$qemu_img_option
			[[ $qemu_img_option =~ ^/dev/.*$ ]]		&& disk=$qemu_img_option
		}

		QEMU_IMG_SIZES+=($size)

		[[ -e $disk ]] ||
		qemu-img create -f qcow2 $disk $size || {
			echo "init $disk failed"
			return 1
		}

		case $disk_type in
		virtio-scsi)
			QEMU_DRIVE_OPTION+="-drive file=$disk,if=none,id=hd$i,media=disk,aio=native,cache=none -device scsi-hd,bus=scsi0.0,drive=hd$i,scsi-id=1,lun=$i "
			;;
		*)
			QEMU_DRIVE_OPTION+="-drive file=$disk,media=disk,if=virtio "
			;;
		esac

	done

	return 0
}

setup_qemu_console()
{
	if [[ "$DISPLAY" ]]; then
		qemu_console_option=
	elif [[ -t 1 ]]; then
		qemu_console_option="-display none -monitor null -serial stdio"
	else
		qemu_console_option="-daemonize -display none -monitor null"
	fi
}

setup_qemu_netdev()
{
	[[ $model == *"-netdev "* ]] && return

	qemu_netdev_option="-device e1000,netdev=net0 "
	qemu_netdev_option+="-netdev user,id=net0"
	[[ $opt_ssh ]] && {
		lsof -Pi :$opt_ssh -sTCP:LISTEN > /dev/null && sleep 5
		qemu_netdev_option+=",hostfwd=tcp::$opt_ssh-:22"
	}
}
