#!/bin/bash

# convert a `-d` option value like 3d/2w/1m/1y into a day count for `find -mtime -N`
# or a `date -d "N days ago"` deadline
opt_date_to_days()
{
	local opt_date=$1

	[[ $opt_date =~ [0-9]+d$ ]] && opt_date=${opt_date%d}
	[[ $opt_date =~ [0-9]+w$ ]] && opt_date=$((${opt_date%w} * 7))
	[[ $opt_date =~ [0-9]+m$ ]] && opt_date=$((${opt_date%m} * 30))
	[[ $opt_date =~ [0-9]+y$ ]] && opt_date=$((${opt_date%y} * 365))

	echo "$opt_date"
}

# convert a `-d` option value into a day-offset range, printed as
# "day_min day_max" (0 = today; day_max is exclusive, empty = unbounded).
# N is a 1-indexed day count -- today is day 1, today-1 is day 2, etc --
# so a bare N[dwm] and <=N both mean "the first N days" (today .. N-1 days
# ago); <N drops the Nth day (the first N-1 days); >N/>=N mean the Nth
# day onward, unbounded. Clauses can be comma-joined for an AND:
#   3          -> day_min=0 day_max=3   (today, today-1, today-2)
#   <1         -> day_min=0 day_max=0   (nothing)
#   <=1        -> day_min=0 day_max=1   (today only)
#   >2         -> day_min=2 day_max=    (today-2 or older, unbounded)
#   >=4        -> day_min=3 day_max=    (today-3 or older, unbounded)
#   <6         -> day_min=0 day_max=5   (today .. today-4)
#   <=6        -> day_min=0 day_max=6   (today .. today-5)
#   >=4,<6     -> day_min=3 day_max=5   (only today-3 and today-4)
#   <=6,>3     -> day_min=3 day_max=6   (today-3 .. today-5)
opt_date_to_range()
{
	local spec=$1
	local day_min=0
	local day_max=
	local clause op num

	IFS=',' read -ra clauses <<<"$spec"
	for clause in "${clauses[@]}"; do
		clause=${clause// /}
		[[ $clause ]] || continue

		if [[ $clause =~ ^\>=(.+)$ ]]; then
			op='>='
			num=${BASH_REMATCH[1]}
		elif [[ $clause =~ ^\<=(.+)$ ]]; then
			op='<='
			num=${BASH_REMATCH[1]}
		elif [[ $clause =~ ^\>(.+)$ ]]; then
			op='>'
			num=${BASH_REMATCH[1]}
		elif [[ $clause =~ ^\<(.+)$ ]]; then
			op='<'
			num=${BASH_REMATCH[1]}
		else
			op='N'
			num=$clause
		fi
		num=$(opt_date_to_days "$num")

		case $op in
		'>=') day_min=$((num - 1)) ;;
		'>') day_min=$num ;;
		'<=') day_max=$num ;;
		'<') day_max=$((num - 1)) ;;
		'N') day_max=$num ;;
		esac
	done

	((day_min < 0)) && day_min=0

	echo "$day_min $day_max"
}

# exit unless running as the lkp user -- guards a cleanup script against a
# human accidentally invoking it under their own account
require_lkp_user()
{
	[[ $(whoami) = lkp ]] || {
		echo 'run as lkp!'
		exit 1
	}
}

# parse the -d/--date <val> and -n/--dry-run flags shared by every
# find-and-clean-old-files script, setting $opt_date/$opt_dryrun as global
# variables in the calling script. Exits on any other argument, same as
# each script's own arg-parsing loop used to.
parse_date_dryrun_opts()
{
	while [[ $# -gt 0 ]]; do
		case $1 in
		-d | --date)
			opt_date=$2
			shift
			;;
		-n | --dry-run) opt_dryrun=1 ;;
		*)
			echo "Unknown parameter passed: $1"
			exit 1
			;;
		esac
		shift
	done
}

# build a `<find_cmd> [-mtime -N] [| grep -E pattern]...` command string --
# appends an mtime filter when opt_date is set (see opt_date_to_days above),
# then one `grep -E` pipe per remaining pattern argument. Caller is
# responsible for eval'ing (and optionally echoing) the result.
build_filtered_find_cmd()
{
	local cmd=$1
	local opt_date=$2
	shift 2

	[[ $opt_date ]] && cmd+=" -mtime -$opt_date"

	local pattern
	for pattern in "$@"; do
		cmd="$cmd | grep -E $pattern"
	done

	echo "$cmd"
}
