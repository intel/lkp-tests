#!/bin/sh

dbg_log()
{
	echo "$(date +%H:%M:%S) $*" >> "$TMP_RESULT_ROOT/lkp.log"
}

die()
{
	echo "$@" 1>&2

	dump_call_stack

	# http://tldp.org/LDP/abs/html/exitcodes.html#EXITCODESREF
	# According to the above table, exit codes 1 - 2, 126 - 165, and 255 [1] have special meanings,
	# and should therefore be avoided for user-specified exit parameters.
	exit 99
}

dump_call_stack()
{
	:
}

[ -z "$BASHPID" ] && return

dump_call_stack()
{
	local stack_depth=${#FUNCNAME[@]}
	local i
	for i in $(seq 0 $stack_depth); do
		[[ $i -eq $stack_depth ]] && break
		echo "  ${BASH_SOURCE[i+1]}:${BASH_LINENO[i]}: ${FUNCNAME[i+1]}" >&2
	done
}

