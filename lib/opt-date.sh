#!/bin/bash

# convert a `-d` option value like 3d/2w/1m into a day count
opt_date_to_days()
{
	local opt_date=$1

	[[ $opt_date =~ [0-9]+d$ ]] && opt_date=${opt_date%d}
	[[ $opt_date =~ [0-9]+w$ ]] && opt_date=$((${opt_date%w} * 7))
	[[ $opt_date =~ [0-9]+m$ ]] && opt_date=$((${opt_date%m} * 30))

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
