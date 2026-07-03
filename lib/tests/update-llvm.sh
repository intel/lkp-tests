#!/bin/bash

. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/debug.sh

# make bpf failed when we use clang under v15 on v6.7 kernel
# prepare_for_llvm works for cluster, for local user, please install clang v15 or newer
# mannually.
prepare_for_llvm()
{
	# Due to some low dependency version issues, the latest version of the llvm_project.cgz package
	# cannot be generated in alios.
	# But bpf must use llvm v15 or higher, so don't run bpf on alios.
	is_aliyunos && die "alios doesn't support bpf due to some dependency issues"

	#   LLVM version 11.0.1
	# Ubuntu LLVM version 14.0.0
	local llvm_version=$(llc --version | grep "LLVM version")
	llvm_version=${llvm_version##* }
	llvm_version=${llvm_version%%.*}
	echo "llvm_version: $llvm_version"
	[[ $llvm_version -ge 15 ]] || {
		echo "Please install llvm-15 or newer before running bpf"
		return 1
	}
}
