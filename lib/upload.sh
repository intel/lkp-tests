#!/bin/sh

. $LKP_SRC/lib/env.sh

is_local_server()
{
	[ "$LKP_SERVER" != "${LKP_SERVER#inn}" ] && return
	[ "$LKP_SERVER" != "${LKP_SERVER#192.168.}" ] && return
	return 1
}

upload_files_rsync()
{
	[ -n "$target_directory" ] && {

		local current_dir=$(pwd)
		local tmpdir=$(mktemp -d)
		cd "$tmpdir"
		mkdir -p ${target_directory}

		rsync -a --no-owner --no-group \
			--chmod=D775,F664 \
			--ignore-missing-args \
			--min-size=1 \
			${target_directory%%/*} rsync://$LKP_SERVER$JOB_RESULT_ROOT/

		local JOB_RESULT_ROOT=$JOB_RESULT_ROOT/$target_directory

		cd $current_dir
		rm -fr "$tmpdir"
	}

	rsync -a --no-owner --no-group \
		--chmod=D775,F664 \
		--ignore-missing-args \
		--min-size=1 \
		"$@" rsync://$LKP_SERVER$JOB_RESULT_ROOT/
}

upload_files_lftp()
{
	local file
	local dest_file
	local ret=0
	local LFTP_TIMEOUT='set net:timeout 2; set net:reconnect-interval-base 2; set net:max-retries 2;'
	local UPLOAD_HOST="http://$LKP_SERVER"

	[ -n "$target_directory" ] && {
		local JOB_RESULT_ROOT=$JOB_RESULT_ROOT/$target_directory
		lftp -c "$LFTP_TIMEOUT; open '$UPLOAD_HOST'; mkdir -p '$JOB_RESULT_ROOT'"
	}

	for file
	do
		if [ -d "$file" ]; then
			[ "$(ls -A $file)" ] && lftp -c "$LFTP_TIMEOUT; open '$UPLOAD_HOST'; mirror -R '$file' '$JOB_RESULT_ROOT/'" || ret=$?
		else
			[ -s "$file" ] || continue
			dest_file=$JOB_RESULT_ROOT/$(basename $file)

			lftp -c "$LFTP_TIMEOUT; open '$UPLOAD_HOST'; put -c '$file' -o '$dest_file'" || ret=$?
		fi
	done

	return $ret
}

upload_one_curl()
{
	local src=$1
	local dest=$2

	if [ -d "$src" ]; then
		(
			cd $(dirname "$1")
			dir=$(basename "$1")
			find "$dir" -type d -exec curl -sSf -X MKCOL "http://$LKP_SERVER$dest/{}" \;
			find "$dir" -type f -size +0 -exec curl -sSf -T '{}' "http://$LKP_SERVER$dest/{}" \;
		)
	else
		[ -s "$src" ] || return
		curl -sSf -T "$src" http://$LKP_SERVER$dest/
	fi
}

upload_files_curl()
{
	local file
	local ret=0

	# "%" character as special character not be allowed in the URL when use curl command to transfer files, details can refer to below:
	# https://www.werockyourweb.com/url-escape-characters/
	local job_result_root=$(echo $JOB_RESULT_ROOT | sed 's/%/%25/g')

	[ -n "$target_directory" ] && {
		local dir
		for dir in $(echo $target_directory | tr '/' ' ')
		do
			job_result_root=$job_result_root/$dir
			curl -sSf -X MKCOL http://$LKP_SERVER$job_result_root  >/dev/null
		done
	}

	for file
	do
		upload_one_curl "$file" "$job_result_root" >/dev/null || ret=$?
	done

	return $ret
}

upload_files_copy()
{
	local RESULT_ROOT="$RESULT_ROOT/$target_directory"


	mkdir -p $RESULT_ROOT

	if [ "$LKP_LOCAL_RUN" != "1" ]; then
		[ -n "$target_directory" ] && {
			chown -R lkp.lkp $RESULT_ROOT
			chmod -R g+w $RESULT_ROOT
		}

		chown -R lkp.lkp "$@"
		chmod -R ug+w "$@"
	fi

	local copy="cp -a"
	local file
	local ret=0

	for file
	do
		[ -s "$file" ] || continue
		[ "$LKP_LOCAL_RUN" = "1" ] && chmod ug+w "$file"
		$copy "$file" $RESULT_ROOT/ || {
			ls -l "$@" $RESULT_ROOT 2>&1
			ret=$?
		}
	done

	return $ret
}

upload_files()
{
	if [ "$1" = "-t" ]; then
		local target_directory="$2"

		shift 2
	fi

	[ $# -ne 0 ] || return

	# NO_NETWORK is empty: means network is avaliable
	# VM_VIRTFS is empty: means it's not a 9p fs(used by lkp-qemu)
	if [ -z "$NO_NETWORK$VM_VIRTFS" ]; then
		[ -z "$JOB_RESULT_ROOT" -a "$LKP_LOCAL_RUN" = "1" ] && { # bin/run-local.sh
			upload_files_copy "$@"
			return
		}

		if has_cmd rsync && is_local_server; then
			upload_files_rsync "$@"
			return
		fi

		if has_cmd lftp; then
			upload_files_lftp "$@"
			return
		fi

		if has_cmd curl; then
			upload_files_curl "$@"
			return
		fi

		if [ -z "$NO_NETWORK" ]; then
			# NFS is the last resort -- it seems unreliable, either some
			# content has not reached NFS server during post processing, or
			# some files occasionally contain some few '\0' bytes.
			upload_files_copy "$@"
			return
		fi
	else
		# 9pfs, copy directly
		upload_files_copy "$@"
		return
	fi
}
