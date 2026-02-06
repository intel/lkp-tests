#!/bin/sh

# When using some options, you must follow the order specified in the usage below.
# usage: git_clone_update https://github.com/pmem/valgrind.git [dir] [--branch master] [--recursive]
git_clone_update()
{
	local url=$1
	local dir
	local branch=master
	shift

	if [ -n "$1" ] && [ "$1" = "${1#-}" ]; then
		dir="$1"
		shift
	else
		dir=$(basename $url .git)
	fi

	if [ "$1" = "--branch" ] && [ -n "$2" ]; then
		branch=$2
	fi

	source_dir=$PWD/$dir

	local git="timeout 60m git"

	if [ -d $dir/.git ]; then
		(
			cd $dir || exit
			while [ $# != 0 ]; do
				if [ "$1" = "--recursive" ]; then
					git submodule update --init --recursive
					break
				fi
				shift
			done
			for retry in 1 2
			do
				echo \
				$git remote update origin
				$git remote update origin 2>&1 ||
				$git remote update origin 2>&1

				echo \
				$git checkout -q origin/$branch
				$git checkout -q origin/$branch 2>&1 && break
			done
		)
	else
		rm -fr "$dir" 2>/dev/null
		echo \
		$git clone -q "$@" $url $dir
		$git clone -q "$@" $url $dir 2>&1 ||
		$git clone -q "$@" $url $dir 2>&1 ||
		$git clone -q "$@" $url $dir
	fi
}
