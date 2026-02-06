#!/bin/sh

[ -n "$LKP_SRC" ] || LKP_SRC="$(dirname "$(dirname "$(readlink -e -v "$0")")")"

msg() {
	message=$1
	path=$2
	echo "$message"
	echo "$message" >> "$path"
}

log_path="./test_install_log"

[ $# != 0 ] && {
	option="$1"
	if [ "$option" = '-o' ]; then
		log_path="$2"
	fi
}

error_path="$log_path/errors"
install_log="$log_path/install_log"

result_log="$log_path/result.log"
_wrong_pkg="$log_path/_wrong_pkg.log"
wrong_pkg="$log_path/wrong_pkg.log"

rm -rf "$install_log"
rm -rf "$error_path"
rm -rf "$_wrong_pkg"
mkdir -p "$error_path"
mkdir -p "$install_log"

i=1
job_files=$(find "$LKP_SRC/jobs/" -type f -name "*.yaml")
job_number=$(echo "$job_files"|wc -w)
for job in $job_files
do
	is_failed=
	msg "$i/$job_number" "$result_log"
	msg "$job" "$result_log"
	i=$((i+1))
	msg "installing packages..." "$result_log"

	job_name=$(basename "$job")
	job_log_file="$install_log/${job_name%%.*}.log"
	
	lkp install "$job" > "$job_log_file" 2>&1

	err=$(grep -E "(No package)|(locate package)" "$job_log_file")
	[ -n "$err" ] && {
		echo "$err" >> "$_wrong_pkg"
		msg "leak some packages" "$result_log"
		is_failed=1
	}

	err=$(grep -E -w -n -r "error|E:|fatal|wrong|fail|failed" "$job_log_file")
	[ -n "$err" ] && {
		echo "$err" > "$error_path/${job_name%%.*}.log"
		is_failed=1
	}
	
	if [ "$is_failed" != 1 ]; then
		msg "successed installing" "$result_log"
	else
		msg 'failed installing' "$result_log"
	fi
	msg '' "$result_log"
done

sort -k2n "$_wrong_pkg" 2> /dev/null | uniq > "$wrong_pkg" && rm "$_wrong_pkg" 2> /dev/null
