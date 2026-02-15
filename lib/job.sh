#!/bin/sh

read_env_vars()
{
	[ -f "$TMP/env.yaml" ] || return 0

	local key
	local val

	while read -r key val
	do
		[ "${key%[a-zA-Z0-9_]:}" != "$key" ] || continue
		key=${key%:}
		export "$key=$val"
	done < $TMP/env.yaml

	return 0
}

wait_post_test_timeout()
{
	$LKP_SRC/bin/event/wait post-test --timeout $1
	ret=$?

	# only wakeup activate-monitor when event catched or timeout
	if [ $ret = 0 ] || [ $ret = 62 ]; then
		$LKP_SRC/bin/event/wakeup activate-monitor

	fi
}

wakeup_pre_test()
{
	mkdir $TMP/wakeup_pre_test-once 2>/dev/null || return

	if [ -n "$monitor_delay" ]; then
		(
			wait_post_test_timeout $monitor_delay

		) &
	else
		$LKP_SRC/bin/event/wakeup activate-monitor
		$LKP_SRC/bin/event/wakeup pre-test # compatibility code, remove after 1 month
	fi
	sleep 1
	date '+%s' > $TMP/start_time
}

should_wait_cluster()
{
	[ -z "$LKP_SERVER" ] && return 1
	[ -z "$node_roles" ] && return 1
	[ "$cluster" = "cs-localhost" ] && return 1
	return 0
}

sync_cluster_state()
{
	local state_option
	[ -n "$1" ] && state_option="&state=$1"
	[ -n "$2" ] && {
		shift 1
		other_options="&$(IFS='&' && echo -n "$*")"
	}

	# the return value matters, do not change ! || to &&
	! should_wait_cluster || {
		local url="cgi-bin/lkp-cluster-sync?cluster=$cluster&node=$HOSTNAME$state_option$other_options"
		# eliminate the first cmdline output from http_get_file
		http_get_cgi "$url" - | tail -n +2
	}
}

wait_cluster_state()
{
	for i in $(seq 100)
	do
		result=$(sync_cluster_state $1)
		case $result in
		'abort')
			break
			;;
		'ready')
			return
			;;
		'finish')
			return
			;;
		'retry')
			;;
		esac
	done

	wakeup_pre_test
	echo "cluster.abort: 1" >> $TMP_RESULT_ROOT/last_state

	[ "$i" -eq 100 ] && {
		sync_cluster_state 'abort'
		echo "cluster.timeout: 1" >> $TMP_RESULT_ROOT/last_state
	}

	exit 1
}

wait_other_nodes()
{
	should_wait_cluster || return

	local program_type=$1
	[ "$program_type" = 'test' ] && echo "${*#test }" >> $TMP/executed-test-programs

	mkdir $TMP/wait_other_nodes-once 2>/dev/null || return

	sync_cluster_state 'write_state' "node_roles=$(echo "$node_roles" | tr -s ' ' '+')" \
					 "ip=$(hostname -I | cut -d' ' -f1)" \
					 "direct_macs=$(echo "$direct_macs" | tr -s ' ' '+')" \
					 "direct_ips=$(echo "$direct_ips" | tr -s ' ' '+')"

	local idx=1
	for mac in $direct_macs
	do
		local device ip
		device=$(ip link | grep -B1 $mac | awk -F': ' 'NR==1 {print $2}')
		ip=$(echo $direct_ips | cut -d' ' -f $idx)
		ip addr add $ip/24 dev $device
		ip link set $device up
		if [ -n "$set_nic_irq_affinity" ]; then
			if [ "$set_nic_irq_affinity" = "1" ]; then
				$LKP_SRC/bin/set_nic_irq_affinity all $device || return
			elif [ "$set_nic_irq_affinity" = "2" ]; then
				$LKP_SRC/bin/set_nic_irq_affinity local $device || return
			else
				echo "Invalid nic irq setting mode, quit..."
				return 1
			fi
		fi
		idx=$((idx + 1))
	done

	# exit if either of the other nodes failed its job

	wait_cluster_state 'wait_ready'

	while read -r line; do
		[ "${line#\#}" != "$line" ] && continue
		# shellcheck disable=SC2163
		export "$line"
	done <<EOF
$(sync_cluster_state 'roles_ip')
EOF
}

# In a cluster test, if some server/service role only started daemon(s) and
# finished the job quickly, wait until the clients have finished with their
# test jobs.
wait_clients_finish()
{
	[ -n "$node_roles" ] || return
	[ "$cluster" = "cs-localhost" ] && return
	[ -f "$TMP/executed-test-programs" ] && return

	# contact LKP server, it knows whether all clients have finished
	wait_cluster_state 'wait_finish'
}

check_exit_code()
{
	local exit_code=$1

	[ "$exit_code" = 0 ] && return

	# when setup scripts fail, the monitors should be wakeup
	wakeup_pre_test

	echo "${program_type}.${program}.exit_code.$exit_code: 1" >> $TMP_RESULT_ROOT/last_state
	echo "exit_fail: 1"				>> $TMP_RESULT_ROOT/last_state
	sync_cluster_state 'failed'
	exit "$exit_code"
}

get_program_name()
{
	local i
	local program

	for i
	do
		[ "$i" != "${i#*=}" ] && continue # skip env NAME=VALUE

		case $i in
		*/bin/run-test|*/bin/run-setup|*/bin/run-daemon|*/bin/run-monitor|*/bin/run-no-stdout-monitor|*/bin/run-one-shot-monitor) continue ;;
		esac

		program=${i##*/}
		echo "${program}"

		return 0
	done

	return 1
}

record_program()
{
	local program
	program=$(get_program_name "$@") || return 1
	echo "${program}" >> $TMP/program_list
	echo "${program}"
}

run_program()
{
	local i
	local has_env=

	local program_type=$1
	shift

	local program="$(record_program "$@")"

	for i
	do
		[ "$i" != "${i#*=}" ] && {	 # env NAME=VALUE
			has_env=1
			break
		}
	done

	if [ -n "$has_env" ]; then
		env "$@"
	else
		"$@"
	fi

	check_exit_code $?
}

run_program_in_background()
{
	local program="$(record_program "$@")"

	if [ "$1" != "${1#*=}" ]; then
		env "$@" &
	else
		"$@" &
	fi
}

run_monitor()
{
	# w/a for watchdog to permit it always runs
	[ "$need_monitors" = "false" ] && [ "${1%%monitors/plain/watchdog}" = "$1" ] && return
	[ "$disable_monitor" = "$1" ] && return

	run_program_in_background "$@"
}

run_setup()
{
	run_program setup "$@"
	read_env_vars
}

start_daemon()
{
	# will be killed by watchdog when timeout
	echo $$ >> $TMP/pid-start-daemon

	# If cs-localhost mode, the pid of daemon is recorded and will be used
	# to kill it in bin/post-run when the task is finished
	if [ "$cluster" = "cs-localhost" ]; then
		# (1) for dash, refer to https://wiki.ubuntu.com/DashAsBinSh
		# local a=5 b=6;
		# in /bin/dash this line makes b a global variable!
		# so neither
		#     local deamon=${@##*/}
		# nor
		#     local deamon=${*##*/}
		# could work on dash (tested on 0.5.10.2-5, default on debian 10)
		# error is like "local: /lkp/lkp/src/daemon/mongodb: bad variable name"
		# (2) for bash, refer to 'man bash'
		# ${parameter##word}
		# If parameter is an array variable subscripted with @ or *, the
		# pattern removal operation is applied to each member of the array
		# in turn, and the expansion is the resultant list.
		# above is not expected in our usage case.
		local daemon="$(get_program_name "$@")"
		run_program_in_background "$@"
		echo $! >> $TMP/pid-bg-proc-$daemon
	else
		run_program daemon "$@"
	fi

	sync_cluster_state 'finished'
	# If failed to start the daemon above, the job will abort.
	# LKP server on notice of the failed job will abort the other waiting nodes.

	wait_other_nodes 'daemon'
	wakeup_pre_test
	wait_clients_finish
}

run_lkp_on_vmm()
{
	[ -x $LKP_SRC/programs/lkp-run-on-qemu/run ] || {
		echo "Run on vmm isn't implemented, abort"
		return 1
	}

	$LKP_SRC/programs/lkp-run-on-qemu/run ${job%.yaml}.sh
}

run_test()
{
	if need_run_on_vmm; then
		run_lkp_on_vmm
	else
		# wait other nodes may block until watchdog timeout,
		# it should be able to killed by watchdog
		echo $$ >> $TMP/pid-run-tests

		wait_other_nodes 'test'
		wakeup_pre_test
		run_program test "$@"
		sync_cluster_state 'finished'
	fi
}

