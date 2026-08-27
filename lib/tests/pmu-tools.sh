#!/bin/sh

# pmu-tools runs on top of Linux perf; refuse virtual machines and set
# up $perf/$PATH to the vendored copy under $BENCHMARK_ROOT/pmu-tools.
pmu_tools_init()
{
	is_virt && die "Don't run pmu-tools on virtual machine"

	set_perf_path "$BENCHMARK_ROOT/pmu-tools/perf"
	export PATH=$BENCHMARK_ROOT/pmu-tools:$PATH
}

# pmu-tools needs to download CPU map file from
# https://download.01.org/perfmon to $XDG_HOME_CACHE/pmu-events at
# first run. But test machine may not have external network
# connection. So we will pre-downloaded CPU map files into
# $BENCHMARK_ROOT and copy it to user's cache directory.
ensure_pmu_events_cache()
{
	[ -n "$HOME" ] || export HOME=/root

	[ -d "$HOME/.cache/pmu-events" ] || {
		mkdir -p "$HOME/.cache"
		cp -af "$BENCHMARK_ROOT/pmu-tools/pmu-events" "$HOME/.cache"
	}
}

cpu_info()
{
	str=$1
	grep -E "${str}[[:space:]]+:" "/proc/cpuinfo" | uniq | cut -d ':' -f 2 | sed -e 's/^[ ]*//g' | sed -e 's/[ ]*$//g'
}

create_links()
{
	pmu_dir="$HOME/.cache/pmu-events"
	cpu_family=$(cpu_info "cpu family")
	model=$(cpu_info "model")
	if [ -z "$cpu_family" ] || [ -z "$model" ]; then
		echo "Can't check cpu family or model from /proc/cpuinfo"
		exit
	fi
	if [ "$cpu_family" -eq 6 ] && [ "$model" -eq 85 ]; then
		stepping=$(cpu_info "stepping")
		[ -z "$stepping" ] && exit
		for f in "$pmu_dir"/GenuineIntel-6-55-*"$stepping"*.json; do
			# remove stepping field from file name.
			# GenuineIntel-6-55-56789ABCDEF-core.json
			name=${f##*-}
			link_name="$pmu_dir/GenuineIntel-6-55-$name"
			ln -sf "$f" "$link_name"
		done
	fi
}
