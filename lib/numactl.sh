#!/bin/sh
# numactl.sh

. "$LKP_SRC/lib/common.sh"
. "$LKP_SRC/lib/debug.sh"

__parse_node_binding()
{
	__config=$1

	if [ -z "$__config" ]; then
		__node_binding_mode="none"
		return
	elif [ "$__config" = "even" ]; then
		__node_binding_mode="even"
		return
	fi
	__even_nodes=$(remove_prefix "$__config" even%)
	if [ -n "$__even_nodes" ]; then
		__node_binding_mode="even-list"
		__even_nodes=$(expand_cpu_list "$__even_nodes")
		__nr_even_node=$(cpu_list_count "$__even_nodes")
	else
		__node_binding_mode="adhoc"
		__nodes="$__config"
	fi
}

parse_numa_node_binding()
{
	[ $# -eq 2 ] || die "2 parameters required"
	__parse_node_binding "$1"
	__cpu_node_binding_mode="$__node_binding_mode"
	__cpu_even_nodes="$__even_nodes"
	__nr_cpu_even_node="$__nr_even_node"
	__cpu_nodes="$__nodes"

	__parse_node_binding "$2"
	__mem_node_binding_mode="$__node_binding_mode"
	__mem_even_nodes="$__even_nodes"
	__nr_mem_even_node="$__nr_even_node"
	__mem_nodes="$__nodes"
}

__node_binding()
{
	__seq_no=$1
	__node_binding_mode=$2
	__even_nodes=$3
	__nr_even_node=$4
	__nodes=$5

	case "$__node_binding_mode" in
	none)
		__binding=
		;;
	even)
		__binding=$((__seq_no % nr_node))
		;;
	even-list)
		__binding=$(cpu_list_ref "$__even_nodes" $((__seq_no % __nr_even_node)))
		;;
	adhoc)
		__binding="$__nodes"
		;;
	esac
}

numa_node_binding()
{
	[ $# -eq 1 ] || die "2 parameters required"
	__seq_no=$1

	__node_binding "$__seq_no" "$__cpu_node_binding_mode" \
		"$__cpu_even_nodes" "$__nr_cpu_even_node" "$__cpu_nodes"
	[ -n "$__binding" ] && __cpu_binding="--cpunodebind=$__binding"
	__node_binding "$__seq_no" "$__mem_node_binding_mode" \
		"$__mem_even_nodes" "$__nr_mem_even_node" "$__mem_nodes"
	[ -n "$__binding" ] && __mem_binding="--membind=$__binding"
	if [ -n "$__cpu_binding" ] || [ -n "$__mem_binding" ]; then
		echo -n "numactl $numactl_opts $__cpu_binding $__mem_binding --"
	fi
}
