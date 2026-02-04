#!/bin/sh

cpu_info()
{
    str=$1
    grep -E "$str[[:space:]]+:" "/proc/cpuinfo" | uniq | cut -d ':' -f 2 | sed -e 's/^[ ]*//g' | sed -e 's/[ ]*$//g'
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
