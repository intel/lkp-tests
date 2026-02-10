#!/bin/bash

get_ignored_and_worked_tests()
{
	all_tests_cmd="$1"
	all_tests=""
	ignored_tests_cmd=""
	ignored_tests=""

	[[ "$2" ]] && cat $2 2>/dev/null | sort | uniq > merged_ignored_files

	[[ -s "merged_ignored_files" ]] && {
		ignored_tests_cmd=${all_tests_cmd}" | grep -F -f merged_ignored_files"
		all_tests_cmd=${all_tests_cmd}" | grep -v -F -f merged_ignored_files"

		ignored_tests=$(eval "$ignored_tests_cmd")
	}
	all_tests=$(eval "$all_tests_cmd")
	[[ -f merged_ignored_files ]] && rm merged_ignored_files > /dev/null 2>&1
}
