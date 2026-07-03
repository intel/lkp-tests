#!/bin/sh

. $LKP_SRC/lib/debug.sh

log_echo()
{
	date=$(date +'%F %T')
	echo "$date $@"
	echo "$@" >>$TMP_RESULT_ROOT/reproduce.sh
}

log_eval()
{
	log_echo "$@"
	eval "$@"
}

log_cmd()
{
	log_echo "$@"
	"$@"
}

log_bg_cmd()
{
	log_echo "$@ &"
	"$@" &
}

log_test()
{
	log_echo "$exec_prefix" "$@"
	"$@"
}

# To make it easy to log something like: echo abc > file
log_write_file()
{
	file="$1"
	shift
	cmdline=echo
	for param; do
		cmdline="$cmdline '$param'"
	done
	cmdline="$cmdline > '$file'"
	log_echo "$cmdline"
	echo "$@" >"$file"
}

# To make it easy to log something like: echo abc >> file
log_append_file()
{
	file="$1"
	shift
	cmdline=echo
	for param; do
		cmdline="$cmdline '$param'"
	done
	cmdline="$cmdline >> '$file'"
	log_echo "$cmdline"
	echo "$@" >>"$file"
}
