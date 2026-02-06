#!/bin/sh

. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/reproduce-log.sh

do_wipefs()
{
	local dev=$1
	local usage

	usage=$(wipefs -h 2>/dev/null) || {
		log_cmd dd if=/dev/zero of=$dev bs=4k count=100 status=noxfer
		return
	}

	if [ "${usage#*--force}" != "$usage" ]; then
		log_cmd wipefs -a --force $dev
	else
		log_cmd wipefs -a $dev
	fi
}

remove_dm()
{
	[ -n "$nr_partitions" ] || return
	has_cmd dmsetup || return

	log_cmd dmsetup remove_all
}

destroy_fs()
{
	for dev in $partitions
	do
		do_wipefs $dev
	done
}

destroy_devices()
{
	remove_dm
	destroy_fs
}

start_o2cb()
{
	# remove the existed node to make sure 'add-cluster' work well
	# we don't care the output and return value
	# Usage: /etc/init.d/o2cb {start|stop|status|restart|try-restart|force-reload}
	o2cb remove-cluster ocfs2single >/dev/null 2>&1
	o2cb add-cluster ocfs2single || return
	o2cb add-node --ip 127.0.0.1 --port 7777 --number 1 ocfs2single "$(hostname)" || return
	o2cb register-cluster ocfs2single || return
	o2cb start-heartbeat ocfs2single || return
	service o2cb force-reload || return
}

start_nfsd()
{
	local mp

	# exportfs: /fs does not support NFS export
	#
	# the solution is to either run this earlier
	#   mountpoint -q /fs || mount -t tmpfs fs /fs
	# or mount --bind to a tmpfs nfsv4 export root.
	#
	mountpoint -q /export || {
		log_cmd mkdir /export
		log_cmd mount -t tmpfs 'nfsv4_root_export' /export
	}
	echo "/export *(fsid=0,rw,no_subtree_check,no_root_squash)" > /etc/exports

	for mp
	do
		log_cmd mkdir -p /export/$mp
		log_cmd mount --bind $mp /export/$mp

		local entry="/export/$mp *(rw,no_subtree_check,no_root_squash)"
		log_eval "echo '$entry' >> /etc/exports"
	done

	log_cmd systemctl restart rpcbind
	log_cmd systemctl restart rpc-statd
	log_cmd systemctl restart nfs-idmapd
	log_cmd systemctl restart nfs-server || {
		systemctl status nfs-kernel-server.service
		cat /etc/exports
		exit 1
	}
}

start_smbd()
{
	# setup smb.conf
	cat >> /etc/samba/smb.conf <<EOF
[fs]
   path = /fs
   comment = lkp cifs
   browseable = yes
   read only = no
EOF
	# setup passwd
	(echo "pass"; echo "pass") | smbpasswd -s -a "$(whoami)"
	# restart service
	systemctl restart smbd.service
}

mount_local_cifs()
{
	local dir
	for dir
	do
		local mnt=/cifs/"$(basename "$dir")"
		local dev=//localhost$dir
		log_cmd mkdir -p $mnt
		log_cmd timeout 5m mount -t cifs $def_mount -o user=root,password=pass $dev $mnt
		local errno=$?
		case $errno in
			0)
				echo "mount cifs success"
				;;
			124)
				echo "mount cifs timeout" >&2
				exit $errno
				;;
			*)
				echo "mount cifs failed"
				exit $errno
				;;
		esac
		cifs_mount_points="${cifs_mount_points}$mnt "
		cifs_server_paths="${cifs_server_paths}$dev "
	done
}

mount_local_nfs()
{
	local dir
	for dir
	do
		local mnt=/nfs/"$(basename "$dir")"
		local dev=localhost:$dir
		log_cmd mkdir -p $mnt
		log_cmd timeout 5m mount -t $fs ${mount:-$def_mount} $mount_option $dev $mnt
		local errno=$?
		case $errno in
			0)
				echo "mount nfs success"
				;;
			124)
				echo "mount nfs timeout" >&2
				exit $errno
				;;
			*)
				echo "mount nfs failed"
				exit $errno
				;;
		esac
		log_cmd touch $mnt/wait_for_nfs_grace_period
		nfs_mount_points="${nfs_mount_points}$mnt "
		nfs_export_paths="${nfs_export_paths}$dir "
	done
}

mount_tmpfs()
{
	local nr_tmpfs=$1
	for i in $(seq 0 $((nr_tmpfs-1))); do
		local mnt=/fs/tmpfs$i
		log_cmd mkdir -p $mnt
		log_cmd mount -t tmpfs ${mount:-$def_mount} $mount_option none $mnt || exit
		mount_points="${mount_points}$mnt "
	done
}

is_null_blk()
{
	local dev=$1
	[ "$(echo "$dev" | grep -Fe "/null")" ]
}

is_mount_on_root()
{
	local dev=$1
	[ "$(df | grep -w $dev | grep -o '\S\+$')" = "/" ]
}
