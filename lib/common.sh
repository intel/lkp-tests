# common utility functions

. $LKP_SRC/lib/debug.sh

is_abs_path()
{
	[[ "${1:0:1}" = "/" ]]
}

abs_path()
{
	local path="$1"
	if is_abs_path $path; then
		echo $path
	else
		echo $PWD/$path
	fi
}

reload_module()
{
	# Force an unconditional unload+reload rather than an idempotent
	# lsmod-then-modprobe check. Some modules (e.g. scsi_debug) create a
	# device whose configuration is fixed at load time, so an
	# already-loaded instance may be a stale leftover from an earlier
	# job/suite with different parameters; reusing it silently would give
	# the test the wrong device. A stateless capability module (e.g.
	# kvm_intel with no extra parameters) has no such "wrong" loaded
	# state, so it only needs a plain lsmod check instead of this helper.
	#
	# Only safe for a single, independent module. Do not use this in a
	# loop to reload several modules that depend on each other (e.g.
	# kvm_intel + kvm) -- unloading/reloading one at a time can fail
	# with "module in use" once an earlier call reloads a module the next
	# one depends on; those cases need their own explicit modprobe -r/
	# modprobe sequence in the caller.
	local module=$1
	shift

	modprobe -r "$module" 2>/dev/null
	modprobe "$module" "$@"
}

echo_run()
{
	echo "$@"
	"$@"
}

echo_exec()
{
	echo "$@"
	exec "$@"
}

query_var_from_yaml()
{
	local key=$1
	local yaml_file=${2:--}
	[ $# -ge 1 ] || die "Invalid parmeters: $*"

	sed -ne "1,\$s/^$key[[:space:]]*:[[:space:]]*\\(.*\\)[[:space:]]*\$/\\1/p" "$yaml_file"
}

# the followings are false, otherwise true
# - null string
# - string starts with 0
# - no
# - false
# - n
parse_bool()
{
	if [ "$1" != "-q" ]; then
		echo_bool=echo
	else
		echo_bool=true
		shift
	fi
	[ -z "$1" ] && { $echo_bool 0; return 1; }
	[ "${1#0}" != "$1" ] && { $echo_bool 0; return 1; }
	[ "${1#no}" != "$1" ] && { $echo_bool 0; return 1; }
	[ "${1#false}" != "$1" ] && { $echo_bool 0; return 1; }
	[ "${1#n}" != "$1" ] && { $echo_bool 0; return 1; }
	$echo_bool 1; return 0
}

expand_cpu_list()
{
	cpu_list=$1
	for pair in $(echo "$cpu_list" | tr ',' ' '); do
		if [ "${pair%%-*}" != "$pair" ]; then
			seq $(echo "$pair" | tr '-' ' ')
		else
			echo "$pair"
		fi
	done
}

cpu_list_count()
{
	cpu_list=$1
	echo $cpu_list | wc -w
}

cpu_list_ref()
{
	cpu_list=$1
	n=$2
	echo $cpu_list | cut -d ' ' -f $((n+1))
}

# if str starts with prefix, output remaining part, otherwise output empty string
remove_prefix()
{
	str=$1
	prefix=$2

	stem=${str#"$prefix"}
	[ "$str" != "$stem" ] && echo -n "$stem"
}

is_rt()
{
	local path=$1
	local bn=$(basename "$path")
	local dn=$(dirname "$path")
	[[ $bn =~ ^[0-9]{1,5}$ ]] &&
		[[ -f "$path/job.yaml" ]] &&
		[[ -f "$dn/stddev.json" ]]
}

is_dir_empty()
{
	[[ -d $1 ]] || return 0
	! find "$1" -mindepth 1 -maxdepth 1 -print -quit | grep -q .
}

get_linux_headers_dir()
{
	local pattern="${1:-linux-headers*}"

	local linux_headers_dir="${LINUX_HEADERS_DIR:-}"

	if [[ -z "$linux_headers_dir" ]]; then
		linux_headers_dir=$(ls -d /usr/src/${pattern} 2>/dev/null | head -1)

		if [[ -z "$linux_headers_dir" ]]; then
			local kbuild_dir="/lib/modules/$(uname -r)/build"
			[[ -d "$kbuild_dir" ]] && linux_headers_dir="$kbuild_dir"
		fi
	fi

	echo "$linux_headers_dir"
}
