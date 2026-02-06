#!/bin/bash

[[ -n "$LKP_SRC" ]] || LKP_SRC="$(dirname "$(dirname "$(readlink -e -v "$0")")")"

. $LKP_SRC/lib/install.sh
. $LKP_SRC/lib/detect-system.sh

export LKP_SRC

list_packages()
{
	xargs cat | grep -hv "^\s*#\|^\s*$" | sort | uniq
}

map_packages()
{
	parse_packages_arch

	[[ "$distro" != "debian" ]] && remove_packages_version && remove_packages_repository

	map_python_packages

	adapt_packages | sort | uniq
}

# shellcheck disable=SC2119
detect_system
distro=$_system_name_lowercase
arch=$(get_system_arch)

echo "arch=$arch, distro=$distro, _system_version=$_system_version" 1>&2

depends=$1
if [[ $depends ]]; then
	generic_packages="$(echo $depends | list_packages)"
else
	generic_packages="$(find $LKP_SRC -type f -name depends\* | list_packages)"
fi

packages=$(map_packages)

[[ "$distro" =~ (debian|ubuntu) ]] && extra_option="--dry-run"

echo "$LKP_SRC/distro/installer/$distro $extra_option" 1>&2
$LKP_SRC/distro/installer/$distro $extra_option $packages
