#!/bin/bash

. $LKP_SRC/lib/run-env.sh
. $LKP_SRC/lib/constant.sh

is_mrt()
{
	local dir=$1
	local -a jobs
	local -a matrix
	matrix=( $dir/matrix.json* )
	[ ${#matrix} -eq 0 ] && return 1
	jobs=( $dir/[0-9]*/job.yaml )
	[ ${#jobs} -ge 1 ]
}

# expand v4.1 etc. to commit SHA1
# eg: /gcc-4.9/v4.1/ => /gcc-4.9/b953c0d234bc72e8489d3bf51a276c5c4ec85345/
expand_tag_to_commit()
{
	local param=$1
	local project=$2
	local git_tag
	local commit

	[[ "$project" ]] || project="linux"

	[[ "$param" =~ (^v[0-9].[0-9]+[-rc0-9_]*$) ]] &&
	{
		git_tag=$BASH_REMATCH
		git_tag="${git_tag%/*}"

		# shellcheck disable=SC2098 # This expansion will not see the mentioned assignment
		# shellcheck disable=SC2097 # This assignment is only seen by the forked process
		commit=$(GIT_WORK_TREE="$GIT_ROOT_DIR/$project" GIT_DIR="$GIT_WORK_TREE/.git" \
				git rev-list -n1 "$git_tag" 2>/dev/null) &&
		[[ $commit ]] && param="${param/$git_tag/$commit}"
	}

	echo "$param"
}

cleanup_path_record_from_patterns()
{

	local pattern
	local flag_pattern=0
	local cmd
	local path_file
	local dot_temp_file
	local match_temp_file

	for pattern
	do
		pattern=$(expand_tag_to_commit $pattern)

		if [[ "$flag_pattern" = "0" ]]; then
			cmd="/${pattern//\//\\/}/"
			flag_pattern=1
		else
			cmd="$cmd && /${pattern//\//\\/}/"
		fi
	done

	[[ -d "/tmp" ]] || mkdir "/tmp" || return
	dot_temp_file=$(mktemp -p /tmp lkp-result-cleanup-path.tmpXXXXXX) || return
	match_temp_file=$(mktemp -p /tmp lkp-result-cleanup-path.tmpXXXXXX) || return
	chmod 664 $dot_temp_file || return

	for path_file in $(grep -l "$pattern" $KTEST_PATHS_DIR/*/????-??-??-* $KTEST_PATHS_DIR/*/.????-??-??-*)
	do
		awk -v file1="$match_temp_file" -v file2="$dot_temp_file"  "BEGIN {modified=0} $cmd {print >> file1; modified=1; next}; \
		{print > file2} END {exit 1-modified}" $path_file &&
		mv -f $dot_temp_file $path_file
		chown .lkp $path_file

	done

	cat $match_temp_file

	rm -f $dot_temp_file
	rm -f $match_temp_file

}

clean_path_record_from_result_root()
{

	local path=$1
	local cmd
	local path_file
	local dot_temp_file

	path=$(expand_tag_to_commit $path)
	cmd="/${path//\//\\/}/"

	[[ -d "/tmp" ]] || mkdir "/tmp" || return
	dot_temp_file=$(mktemp -p /tmp lkp-result-cleanup-path.tmpXXXXXX)
	chmod 664 $dot_temp_file || return

	if [[ $(find $KTEST_PATHS_DIR -type f -name ".????-??-??-*" 2>/dev/null) ]]; then
		paths=$(grep -s -l "$path" $KTEST_PATHS_DIR/*/????-??-??-* $KTEST_PATHS_DIR/*/.????-??-??-*)
	else
		paths=$(grep -s -l "$path" $KTEST_PATHS_DIR/*/????-??-??-*)
	fi

	for path_file in $paths
	do
		lockfile-create -q --use-pid --retry 10 --lock-name "$path_file".lock

		awk "BEGIN {modified=0} $cmd {modified=1;next}; {print} END {exit 1-modified}" $path_file > $dot_temp_file &&
		mv -f $dot_temp_file $path_file
		chown .lkp $path_file

		lockfile-remove --lock-name "$path_file".lock
	done

	rm -f $dot_temp_file
}
