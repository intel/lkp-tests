#!/bin/sh

. $LKP_SRC/lib/detect-system.sh

sync_distro_sources()
{
	detect_system
	distro=$_system_name_lowercase
	distro_version=$_system_version

	case $distro in
	debian|ubuntu) apt-get update ;;
	fedora)
		if [ $distro_version -ge 22 ]; then
			dnf update
		else
			yum update
		fi ;;
	redhat) yum update ;;
	archlinux) yay -Sy --needed;;
	opensuse)
		zypper update ;;
	oracle) yum update ;;
	*) echo "Not support $distro to do update" ;;
	esac
}

adapt_package()
{
	local pkg_name=$1
	local distro_file=$2
	[ -z "$distro_file" ] && return 1
	[ -f "$distro_file" ] || return 1
	grep "^$pkg_name:" $distro_file
}

# To adapt packages between distributions, use Debian as the default distribution.
# There are two kinds of packages, packages provided by distribution and packages installed by makepkg
# The priority for package adaptation is as follow:
# - adaptation by makepkg, via $LKP_SRC/distro/adaptation-pkg/$distro
# - adaptation by distro version explicitly, via $LKP_SRC/distro/adaptation/$distro-$_system_version
# - adaptation by distro explicitly, via $LKP_SRC/distro/adaptation/$distro
# - default to input package name, not found in above
adapt_packages()
{
	local distro_file distro_ver_file
	if [ -z "$PKG_TYPE" ]; then
		distro_ver_file="$LKP_SRC/distro/adaptation/$distro-$_system_version"
		distro_file="$LKP_SRC/distro/adaptation/$distro"
	else
		distro_file="$LKP_SRC/distro/adaptation-$PKG_TYPE/$distro"
	fi

	local distro_pkg=

	for pkg in $generic_packages
	do
		local mapping=""
		local is_arch_dep="$(echo $pkg | grep ":")"
		if [ -n "$is_arch_dep" ]; then
			[ -f "$distro_ver_file" ] && mapping="$(adapt_package $pkg $distro_ver_file | tail -1)"
			[ -z "$mapping" ] && mapping="$(adapt_package $pkg $distro_file | tail -1)"
		else
			[ -f "$distro_ver_file" ] && mapping="$(adapt_package $pkg $distro_ver_file | head -1)"
			[ -z "$mapping" ] && mapping="$(adapt_package $pkg $distro_file | head -1)"
		fi
		if [ -n "$mapping" ]; then
			distro_pkg=$(echo $mapping | awk -F": " '{print $2}')
			if [ -n "$distro_pkg" ]; then
				echo $distro_pkg
			else
				distro_pkg=${mapping%%::*}
				[ "$mapping" != "$distro_pkg" ] && [ -n "$distro_pkg" ] && echo $distro_pkg
			fi
		else
			[ -z "$PKG_TYPE" ] && echo $pkg
		fi
	done
}

remove_packages_version()
{
	generic_packages=$(echo $generic_packages | sed 's/=[^ ]*//g')
}

remove_packages_repository()
{
	generic_packages=$(echo $generic_packages | sed 's#/[^= ]*##g')
}

# ARCH info has been introduced to handle different ARCHs in single depends file.
# $generic_packages may contains ARCH info such as "liblsan0 (x86_64)"
# This function remove packages that don't match current system ARCH and
# also ARCH info itself for packages that match current system ARCH.
parse_packages_arch()
{
	local arch=$(get_system_arch)
	#remove space between package name and ARCH info
	#"liblsan0 (x86_64)" => "liblsan0(x86_64)"
	generic_packages=$(echo $generic_packages | sed 's/ (/(/g')

	#remove ARCH info for packages that match current system ARCH
	#"liblsan0(x86_64)" ==> "liblsan0" if current system ARCH is x86_64
	generic_packages=$(echo $generic_packages | sed "s/(${arch})//g")

	#remove packages that don't match currect system ARCH
	#"liblsan0(i386)" ==> "" if current system ARCH is x86_64
	generic_packages=$(echo $generic_packages | sed 's/[^ ]*([^ ]*)//g')
}

get_dependency_packages()
{
	local distro=$1
	local script=$2
	local PKG_TYPE=$3
	local base_file="$LKP_SRC/distro/depends/${script}"

	[ -f "$base_file" ] || return

	local generic_packages="$(sed 's/#.*//' "$base_file")"
	detect_system
	parse_packages_arch
	[ "$distro" != "debian" ] && remove_packages_version && remove_packages_repository

	adapt_packages | sort | uniq
}

get_build_dir()
{
	echo "/tmp/build-$1"
}

build_depends_pkg() {
	if [ "$1" = '-i' ]; then
		# in recursion install the package with -i option
		local INSTALL='-i'
		shift
	else
		# only pack the package
		local INSTALL='--noarchive'
	fi
	local script=$1
	local dest=$2
	local pkg
	local pkg_dir

	if [ -z "$BM_NAME" ]; then
		BM_NAME="$script"
		unset_bmname=1
	fi

	# install the dependencies (including -dev ones) to build pkg
	local debs=$(get_dependency_packages $DISTRO ${script})
	local dev_debs=$(get_dependency_packages $DISTRO ${script}-dev)
	debs="$(echo $debs $dev_debs | tr '\n' ' ')"
	if [ -n "$debs" ] && [ "$debs" != " " ]; then
		$LKP_SRC/distro/installer/$DISTRO $debs
	fi

	local packages="$(get_dependency_packages ${DISTRO} ${script} pkg)"
	local dev_packages="$(get_dependency_packages ${DISTRO} ${script}-dev pkg)"
	packages="$(echo $packages $dev_packages | tr '\n' ' ')"
	if [ -z "$packages" ] || [ "$packages" = " " ]; then
		if [ "$BM_NAME" = "$script" ] && [ -z "$PACKAGE_LIST" ]; then
			echo "empty deps for $BM_NAME"
			return 1
		else
			return 0
		fi
	fi

	for pkg in $packages; do
		# pack and install dependencies of pkg
		build_depends_pkg -i $pkg "$dest"
		pkg_dir="$LKP_SRC/pkg/$pkg"
		if [ -d "$pkg_dir" ]; then
			(
				cd "$pkg_dir" && \
				PACMAN="$LKP_SRC/sbin/pacman-LKP" "$LKP_SRC/sbin/makepkg" $INSTALL --config "$LKP_SRC/etc/makepkg.conf" --skippgpcheck
				cp -rf "$pkg_dir/pkg/$pkg"/* "$dest"
				rm -rf "$pkg_dir/"{src,pkg}
			)
		fi
	done

	if [ "$BM_NAME" = "$script" ] && [ -n "$unset_bmname" ]; then
		unset BM_NAME
		unset unset_bmname
	fi
}

parse_yaml() {
	local s='[[:space:]]*'
	local w='[a-zA-Z0-9_-]*'
	local tmp_filter="$(mktemp /tmp/lkp-install-XXXXXXXXX)"

	ls -LR $LKP_SRC/setup $LKP_SRC/monitors $LKP_SRC/tests $LKP_SRC/daemon > $tmp_filter
	scripts=$(cat $1 | sed -ne "s|^\($s\):|\1|" \
	         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\2|p" \
	         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\2|p" | grep -x -F -f \
	         $tmp_filter | grep -v -e ':$' -e '^$' | sort -u)
	rm "$tmp_filter"
}
