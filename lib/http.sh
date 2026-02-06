#!/bin/sh

. $LKP_SRC/lib/env.sh

escape_cgi_param()
{
	local uri="$1"
	# uri=${uri//%/%25} # must be the first one
	# uri=${uri//+/%2B}
	# uri=${uri//&/%26}
	# uri=${uri//\?/%3F}
	# uri=${uri//@/%40}
	# uri=${uri//:/%3A}
	# uri=${uri//;/%3D}
	echo "$uri" |
	sed -r	-e 's/%/%25/g' \
		-e 's/\+/%2B/g' \
		-e 's/&/%26/g' \
		-e 's/#/%23/g' \
		-e 's/\?/%3F/g' \
		-e 's/ /%20/g'
}

reset_broken_ipmi()
{
	[ -f "$RESULT_MNT/.IPMI-reset/$HOSTNAME" ] || return
	[ -x '/usr/sbin/bmc-device' ] || return

	bmc-device --cold-reset
	mv -f $RESULT_MNT/.IPMI-reset/$HOSTNAME $RESULT_MNT/.IPMI-reset/.$HOSTNAME
}

#
# job handling at client is finished, tell server to do some
# post handling, such as delete the job file, process all
# monitors data, and so on
#
trigger_post_process()
{
	http_get_cgi "cgi-bin/lkp-post-run?job_file=$(escape_cgi_param "$job")"

	reset_broken_ipmi
}

jobfile_append_var()
{
	[ -n "$job" ] || return

	# input example: "var1=value1" "var2=value2 value_with_space" ....
	[ -z "$*" ] && LOG_ERROR "no paramter specified at $FUNCTION" && return

	local query_str="job_file=$(escape_cgi_param "$job")"
	for assignment in "$@"; do
		query_str="${query_str}&$(escape_cgi_param "$assignment")"
	done

	http_get_cgi "cgi-bin/lkp-jobfile-append-var?$query_str"
}

set_job_state()
{
	jobfile_append_var "job_state=$1"
}

set_tbox_wtmp()
{
	local tbox_state="$1"
	[ -n "$tbox_state" ] || return

	local query_str="tbox_name=$HOSTNAME&tbox_state=$tbox_state"

	[ -n "$job" ] && is_virt && query_str="${query_str}&job_file=$(escape_cgi_param "$job")"

	http_get_cgi "cgi-bin/lkp-wtmp?$query_str"
}

####################################################

http_escape_request()
{
	local path="$(escape_cgi_param "$1")"
	shift
	http_do_request "$path" "$@"
}

http_do_request()
{
	local path="$1"
	shift

	{ [ -n "$NO_NETWORK$VM_VIRTFS" ] || [ -z "$LKP_SERVER$HTTP_PREFIX" ]; } && {
		echo skip http request: $path "$@"
		return
	}

	# $ busybox wget http://XXX:/
	# wget: bad port spec 'XXX:'
	local http_prefix

	if [ -n "$HTTP_PREFIX" ]; then
		http_prefix="$HTTP_PREFIX"
	else
		http_prefix="http://$LKP_SERVER:${LKP_CGI_PORT:-80}/~$LKP_USER"
	fi

	echo \
	$http_client_cmd "$http_prefix/$path" "$@"
	$http_client_cmd "$http_prefix/$path" "$@"
}

http_setup_client()
{
	[ -n "$http_client_cmd" ] && return

	. $LKP_SRC/lib/wget.sh	&& return
	. $LKP_SRC/lib/curl.sh	&& return
	. $LKP_SRC/lib/wget_busybox.sh	&& return

	echo "Cannot find wget/curl." >&2
	return 1
}

check_create_base_dir()
{
	[ -z "$1" ] && return

	local path="$(dirname "$1")"
	[ -d "$path" ] || mkdir -p "$path"
}

http_get_newer_can_skip()
{
	[ -s "$2" ] || return

	# versioned files can be safely cached without checking timestamp
	[ "${1%-????-??-??.cgz}" != "$1" ] && return
	[ "${1%_????-??-??.cgz}" != "$1" ] && return
}

http_get_file()
{
	http_setup_client && http_get_file "$@"
}

http_get_directory()
{
	http_setup_client && http_get_directory "$@"
}

http_get_newer()
{
	http_setup_client && http_get_newer "$@"
}

http_get_cgi()
{
	http_setup_client && http_get_cgi "$@"
}
