#!/bin/bash

. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/install.sh
. $LKP_SRC/lib/reproduce-log.sh

get_benchmark_path()
{
	# pkgdir is like /tmp/lkp/dbench/pkg/dbench
	echo "${pkgdir}/lkp/benchmarks/${pkgname}"
}

prepare_benchmark_path()
{
	export benchmark_path=$(get_benchmark_path)
}

get_src_pkg_dir()
{
	local pkgname=${1:-$pkgname}

	# srcdir is like /tmp/lkp/dbench/src
	echo "$srcdir/$pkgname"
}

cd_src_pkg_dir()
{
	local src_pkg_dir=$(get_src_pkg_dir $1)

	log_cmd cd $src_pkg_dir
}

rename_versioned_src_pkg_dir()
{
	local versioned_pkgname=${1:-$pkgname-$pkgver}

	log_cmd mv "$srcdir/$versioned_pkgname" "$srcdir/$pkgname"
}

# Args: everything before '--' goes to configure, everything after to make
make_src_pkg()
{
	local configure_args=()
	local make_args=()
	local args_name="configure_args"

	for arg in "$@"; do
		if [[ "$arg" == "--" ]]; then
			args_name="make_args"
			continue
		fi

		eval "${args_name}+=(\"$arg\")"
	done

	cd_src_pkg_dir

	[[ -x "autogen.sh" ]] && ./autogen.sh
	[[ -x "configure" ]] && ./configure "${configure_args[@]}"

	make -j$(nproc) "${make_args[@]}"
}

make_install_src_pkg()
{
	cd_src_pkg_dir

	make install $@
}

pip3_install()
{
	local package=$1

	local options
	pip3 install -h | grep -q break-system-packages && options="--break-system-packages"

	pip3 install $options $package
}

build_pahole()
{
	cd_src_pkg_dir pahole

	mkdir build
	cd build

	log_cmd mkdir -p $pkgdir/usr
	log_cmd cmake -D__LIB=lib -DCMAKE_INSTALL_PREFIX=$pkgdir/usr ..
	log_cmd make install
}

build_dropwatch()
{
	cd_src_pkg_dir dropwatch

	# when use latest 1.5.4 in Debian 10, compile error:
	# configure: error: libreadline is required
	# ==> ERROR: A failure occurred in build().
	#    Aborting...
	# so, keeps 1.5.3 in Debian 10/Debian 11.
	local distro=$(basename $rootfs)
	if [[ "$distro" == *"debian-12"* ]]; then
		git checkout v1.5.4
	else
		git checkout v1.5.3
	fi

	./autogen.sh
	./configure --prefix=$benchmark_path/$pkgname/dropwatch
	make 2>&1
	make install
}

build_iproute2()
{
	cd_src_pkg_dir iproute2-next

	./configure
	make 2>&1
	DESTDIR=$benchmark_path/$pkgname/iproute2-next make install
}

build_edk2()
{
	cd_src_pkg_dir edk2

	source edksetup.sh BaseTools

	git submodule update --init --recursive

	log_cmd make -C BaseTools/Source/C 2>&1

	# generate Build/OvmfX64/DEBUG_GCC*/FV/OVMF.fd
	log_cmd OvmfPkg/build.sh -a X64 -n 112
}

pack_edk2()
{
	pack_contents "$srcdir/edk2/Build/OvmfX64/DEBUG_GCC*/FV/OVMF.fd" "${pkgdir}/lkp/benchmarks/edk2/Build/OvmfX64/DEBUG_GCC/FV"
}

pack_avocado_vt()
{
	local avocado_data_dir=$1
	local avocado_conf_file=/etc/avocado/avocado.conf

	pip3_install avocado-framework
	pip3_install git+https://github.com/avocado-framework/avocado-vt

	log_cmd mkdir -p "$(dirname $avocado_conf_file)"
	log_cmd mkdir -p "$avocado_data_dir"

	cat <<EOT > $avocado_conf_file
[datadir.paths]
data_dir = $avocado_data_dir
EOT

	log_cmd avocado vt-bootstrap --yes-to-all --vt-type qemu

	# reduce package size
	rm -rf $avocado_data_dir/avocado-vt/images/*
	find $avocado_data_dir/avocado-vt/virttest/test-providers.d -name .git -type d | xargs -P$(nproc) rm -rf

	pack_contents "$avocado_conf_file"
	pack_contents "$avocado_data_dir"

	# packages location
	#   debian: /usr/lib/python3/dist-packages/ and /usr/local/lib/python3.x/dist-packages/
	#   centos: /usr/lib/python3.x/site-packages/ and /usr/local/lib/python3.x/site-packages/
	pack_contents /usr/lib/python3*

	# /usr/local/lib/python3.11/dist-packages# ls -d avocado*
	# avocado  avocado_framework-107.0.egg-info  avocado_framework_plugin_vt-104.0.dist-info  avocado_vt
	#
	# # find / -name pytest
	# /usr/local/bin/pytest
	# /usr/local/lib/python3.9/site-packages/pytest
	pack_contents /usr/local
}

# pack_contents /usr/lib/python3
# pack_contents "$srcdir/lkvs/KVM" "${pkgdir}/lkp/benchmarks/lkvs"
pack_contents()
{
	if [[ "$#" == 0 ]]; then
		echo "$FUNCNAME: miss argument" 1>&2
		return 1
	elif [[ "$#" == 1 ]]; then
		local src="$1"
		[[ $src ]] || return

		pack_contents "$src" "$pkgdir/$(dirname $src)"
	else
		# last argument is dst_dir
		mkdir -p "${!#}"

		log_cmd cp -a $@
	fi
}

pack_src_pkg_contents()
{
	local dst_dir=${DESTDIR:-$benchmark_path}
	local src_pkg_dir=$(get_src_pkg_dir)

	if [[ "$#" == 0 ]]; then
		pack_contents "$src_pkg_dir/." "$dst_dir"
	else
		(
			cd $src_pkg_dir

			pack_contents $@ "$dst_dir"
		)
	fi
}

pack_src_pkg_execs()
{
	local exec_prefix=$1

	mkdir -p $benchmark_path

	(
		cd $(get_src_pkg_dir)

		if [[ "$exec_prefix" ]]; then
			find . -maxdepth 1 -type f -executable -name "${exec_prefix}*" -exec cp -a {} $benchmark_path \;
		else
			find . -maxdepth 1 -type f -executable ! -name ".*" -exec cp -a {} $benchmark_path \;
		fi
	)
}

update_submodules()
{
	git submodule update --init --recursive
}

pkgbuild_build_qemu()
{
	local qemu_branch=$1
	local qemu_commit=$2
	local qemu_config=x86_64-softmmu

	[[ -n "$qemu_commit" ]] || return
	[[ -n "$qemu_branch" ]] || return

	local qemu_remote=${qemu_branch%%/*}

	cd_src_pkg_dir $qemu_remote

	log_cmd git checkout -q $qemu_commit

	update_submodules

	log_cmd ./configure --target-list="$qemu_config" --disable-docs --enable-kvm --prefix=${pkgdir}/usr

	unset LDFLAGS
	log_cmd make -j $nr_cpu 2>&1
}

pack_qemu()
{
	local qemu_branch=$1
	[[ -n "$qemu_branch" ]] || return

	local qemu_remote=${qemu_branch%%/*}

	cd_src_pkg_dir $qemu_remote

	log_cmd make install V=1

	# create /bin/kvm link that app like avocado list requires kvm bin
	log_cmd ln -s qemu-system-x86_64 $pkgdir/usr/bin/kvm
}

pack_to_cgz()
{
	local output="$1"
	shift
	cpio -o -H newc --quiet "$@" | gzip -n -9 > "$output"
}

prepare()
{
	prepare_benchmark_path
}

build()
{
	make_src_pkg
}

package()
{
	pack_src_pkg_contents
}
