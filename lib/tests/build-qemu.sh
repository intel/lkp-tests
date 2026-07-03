#!/bin/bash

. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/install.sh
. $LKP_SRC/lib/reproduce-log.sh

QEMU_REPO_ROOT="$BENCHMARK_ROOT/qemu"
QEMU="$QEMU_REPO_ROOT/build/qemu-system-x86_64"

update_submodules()
{
	git submodule update --init --recursive
}

build_qemu()
{
	[ -n "$qemu_config" ] || die "can not find qemu_config"
	[ -n "$qemu_commit" ] || die "can not find qemu_commit"
	[ -n "$qemu_branch" ] || die "can not find qemu_branch"

	local qemu_remote=${qemu_branch%%/*}

	git_clone_update https://gitlab.com/qemu-project/$qemu_remote.git "$QEMU_REPO_ROOT" 2>&1 || die "failed clone qemu tree $qemu_remote"

	cd "$QEMU_REPO_ROOT" || die "fail to enter $QEMU_REPO_ROOT"

	log_cmd git checkout -q $qemu_commit || die "failed to checkout qemu commit $qemu_commit"

	update_submodules || die "fail to update submodules"

	log_cmd ./configure --target-list="$qemu_config" --disable-docs || die "failed to run ./configure"

	unset LDFLAGS
	log_cmd make -j $nr_cpu 2>&1 || die "failed to make"

	$QEMU --help >/dev/null || die "QEMU Emulator can not work normally."
}
