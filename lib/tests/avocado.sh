#!/bin/bash

. $LKP_SRC/lib/reproduce-log.sh
. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/upload.sh
. $LKP_SRC/lib/detect-system.sh

avocado_conf_file="/etc/avocado/avocado.conf"
avocado_data_dir="/lkp/benchmarks/avocado/data"
avocado_result_dir="/tmp/avocado/result"

detect_system
distro=$_system_name_lowercase

setup_conf()
{
	[[ -f $avocado_conf_file ]] || return

	log_cmd mkdir -p "$avocado_result_dir" || return

	# After test finished, upload $base_dir which includes all testting info.
	cat <<EOT >> $avocado_conf_file
logs_dir = $avocado_result_dir
EOT

	local avocado_data_dir=$1
	[[ $avocado_data_dir ]] || return 0

	log_cmd rm -rf $avocado_data_dir
	log_cmd mkdir -p "$(dirname $avocado_data_dir)" || return
	log_cmd cp -r /lkp/benchmarks/avocado/data "$(dirname $avocado_data_dir)/"

	log_cmd sed -i "s|data_dir = .*|data_dir = $avocado_data_dir|g" "$avocado_conf_file"
}

run_test()
{
	local config_file=$1

	if [[ $config_file ]]; then
		log_cmd avocado run --vt-config $config_file 2>&1
	else
		# avocado-vt type_specific.lkvs.tdx_disable
		# avocado-vt type_specific.io-github-autotest-qemu.blockdev_commit_backing_file
		# avocado-vt io-github-autotest-qemu.vlan.vlan_connective_test
		# avocado-vt type_specific.lkvs.boot_check.vm.16G.208_cpu
		echo "$group total tests $(avocado list | grep \.$group | wc -l)"

		local test
		log_cmd avocado list | grep \.$group | cut -d' ' -f2 | while read -r test; do
			log_cmd avocado run $test 2>&1
		done
	fi
}

setup_env()
{
	echo "${FUNCNAME[0]}: distro=$distro"

	local kvm_intel_parameters_tdx=/sys/module/kvm_intel/parameters/tdx

	log_cmd cat $kvm_intel_parameters_tdx
	[[ $(cat $kvm_intel_parameters_tdx) = Y ]] || {
		log_cmd modprobe -rv kvm_intel kvm
		log_cmd modprobe -v kvm_intel tdx=1
		log_cmd cat $kvm_intel_parameters_tdx
	}

	# required for lkvs
	lsmod | grep tun || modprobe tun

	if [[ $distro =~ centos ]]; then
		setup_env_for_centos
	else
		setup_env_for_debian
	fi
}

setup_env_for_debian()
{
	sed -i '/^Environment=LIBVIRTD_ARGS="--timeout/d' /lib/systemd/system/libvirtd.service

	log_cmd systemctl daemon-reload

	log_cmd systemctl restart libvirtd || return
	sleep 60
	log_cmd systemctl status libvirtd

	# create virbr0 interface that is a virtual network bridge
	log_cmd virsh net-start default
	ip ad | grep virbr0 || return

	# The standard package for Open vSwitch on Debian is named openvswitch-switch, while avocado-vt requires to restart the openvswitch service
	log_cmd mv /lib/systemd/system/openvswitch-switch.service /lib/systemd/system/openvswitch.service
	log_cmd sed -i 's/openvswitch-switch/openvswitch/g' /lib/systemd/system/openvswitch.service
	# to recognize the new service file
	log_cmd systemctl daemon-reload
}

setup_env_for_centos()
{
	# [Service]
	# Type=notify
	# Environment=LIBVIRTD_ARGS="--timeout 120"
	# EnvironmentFile=-/etc/sysconfig/libvirtd
	# ExecStart=/usr/sbin/libvirtd $LIBVIRTD_ARGS
	sed -i '/^Environment=LIBVIRTD_ARGS="--timeout/d' /usr/lib/systemd/system/libvirtd.service

	log_cmd systemctl daemon-reload

	log_cmd systemctl restart libvirtd || return
	sleep 60
	log_cmd systemctl status libvirtd

	ip ad | grep virbr0
}

install_lkvs_tests()
{
	cat <<EOT > $avocado_data_dir/avocado-vt/virttest/test-providers.d/lkvs.ini
[provider]
uri: file:///lkp/benchmarks/lkvs

[qemu]
subdir: KVM/qemu
EOT

	# to install the lkvs tests actually
	log_cmd avocado vt-bootstrap --vt-no-downloads --vt-type qemu

	avocado list | grep lkvs | sort > $avocado_result_dir/tests
}
