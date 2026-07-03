#!/bin/bash

KBUILD_SUPPORTED_ARCHS="alpha
arc
arm
arm64
csky
hexagon
i386
loongarch
m68k
microblaze
mips
openrisc
parisc
parisc64
nios2
powerpc
powerpc64
riscv
s390
sh
sparc
sparc64
um
x86_64
xtensa
"

warn_empty()
{
	[[ "$1" ]] && return

	echo "empty parameter" >&2
	return 1
}

is_supported_compiler_option()
{
	local compiler_bin=$1
	local option=$2

	# $ gcc-7 -finvalid -Winvalid -xc /dev/null 2>&1
	# gcc-7: error: unrecognized command line option '-finvalid'; did you mean '-finline'?
	# gcc-7: error: unrecognized command line option '-Winvalid'; did you mean '-Winline'?
	#
	# $ gcc-7 -Werror=attribute-alias -xc /dev/null
	# cc1: error: -Werror=attribute-alias: no option -Wattribute-alias
	# $ gcc-7 -Wno-error=attribute-alias -xc /dev/null
	# cc1: error: -Werror=attribute-alias: no option -Wattribute-alias
	#
	# $ gcc-11 -Winvalid-option -xc /dev/null
	# gcc-11: error: unrecognized command-line option ‘-Winvalid-option’; did you mean ‘-Winvalid-pch’?
	#
	# $ clang-15 -Winvalid-option -finvalid -xc /dev/null
	# warning: unknown warning option '-Winvalid-option' [-Wunknown-warning-option]
	#
	# $ clang-15 -finvalid -xc /dev/null 2>&1
	# clang-15: error: unknown argument: '-fstrict-flex-arrays=3'

	# if an option is "-Wno-<diagnostic-type>", need to remove "no" and check the the remaining flag.
	#
	# $ gcc-7 -Wno-attribute-alias -xc /dev/null
	# /usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/7/../../../x86_64-linux-gnu/Scrt1.o: in function `_start':
	# (.text+0x17): undefined reference to `main'
	# collect2: error: ld returned 1 exit status
	#
	# $ gcc-7 -Wattribute-alias -xc /dev/null
	# gcc-7: error: unrecognized command line option '-Wattribute-alias'; did you mean '-Wattributes'?

	# delete the "no-" prefix only for warning options
	echo $option | grep -q -e "Werror" -e "Wno-error" || option=${option//-Wno-/-W}

	$compiler_bin $option -xc /dev/null 2>&1 | grep -q \
		-e "unrecognized command.line option" \
		-e "no option" \
		-e "unknown warning option" \
		-e "unknown argument" \
		&& return 1

	return 0
}

add_kcflag()
{
	local flag=$1
	is_supported_compiler_option "$compiler_bin" "$flag" && kcflags="$kcflags $flag"
}

add_kbuild_kcflags()
{
	local kcflags_file=$1
	while read flag
	do
		add_kcflag "$flag"
	done < <(grep -v -e "^#" -e "^$" $kcflags_file)
}

is_llvm_equal_one_supported()
{
	local compiler=$1
	local clang_version=${compiler#clang-}

	# handle v2.6.X version, similar to is_clang_supported_arch function
	local kernel_version_major=${kernel_version_major%%.*}

	# LLVM=1 is introduced by below commit
	# [v5.7-rc1] a0d1c951ef08 ("kbuild: support LLVM=1 to switch the default tools to Clang/LLVM")
	is_kernel_version "<" 5.7 && return 1

	if [[ $ARCH = "s390" ]]; then
		# [v6.9-rc2] 978fa00eb035 ("Documentation/llvm: Note s390 LLVM=1 support with LLVM 18.1.0 and newer")
		(( clang_version < 18 )) && return 1
	elif [[ $ARCH = sparc64 ]]; then
		# [v6.13-rc1] f6dee26d26e3 ("sparc/build: Add SPARC target flags for compiling with clang")
		#    * - sparc (sparc64 only)
		#      - ``CC=clang LLVM_IAS=0`` (LLVM >= 20)
		return 1
	elif [[ $ARCH == *"powerpc"* || $ARCH == *"mips"* || $ARCH == *"riscv"* ]]; then
		# https://www.kernel.org/doc/html/v5.18/kbuild/llvm.html
		# https://www.kernel.org/doc/html/v5.19/kbuild/llvm.html
		is_kernel_version "<" 5.18 && return 1
	fi

	return 0
}

setup_llvm_ias()
{
	local opt_cc=$1

	if [[ $ARCH == *"powerpc"* ]]; then
		# [v5.15-rc1] f12b034afeb3 ("scripts/Makefile.clang: default to LLVM_IAS=1")
		# Above commit enables clang integrated assembler by default, which raises below errors:
		# clang-14: error: unsupported argument '-mpower4' to option 'Wa,'
		# clang-14: error: unsupported argument '-many' to option 'Wa,'
		# explicitly set LLVM_IAS=0 to disable integrated assembler and switch back to gcc assembler
		is_kernel_version ">" 5.14 && is_kernel_version "<" 5.18 && echo "LLVM_IAS=0"
	elif [[ $ARCH == *"hexagon"* ]]; then
		is_kernel_version "<" 5.15 && echo "LLVM_IAS=1"
	elif [[ $ARCH =~ arm ]]; then
		is_kernel_version "<" 5.15 && [[ $opt_cc = "LLVM=1" ]] && echo "LLVM_IAS=1"
	elif [[ $ARCH = sparc64 ]]; then
		# [v6.13-rc1] f6dee26d26e3 ("sparc/build: Add SPARC target flags for compiling with clang")
		echo "LLVM_IAS=0"
	fi
}

src_arch()
{
	local ARCH=$1

	case $ARCH in
		i386|x86_64)
			echo x86;;
		sparc32|sparc64)
			echo sparc;;
		parisc|parisc64)
			echo parisc;;
		sh64)
			echo sh;;
		tilepro|tilegx)
			echo tile;;
		powerpc64)
			echo powerpc;;
		*)
			echo $ARCH;;
	esac
}

get_config_value()
{
	local config=$1
	local config_file=$2

	grep -s -h "^$config=" $config_file .config $KBUILD_OUTPUT/.config $BUILD_DIR/.config |
		head -n1 |
		cut -f2- -d= |
		sed 's/\"//g'
}

# is_config_enabled CONFIG_BOOT_LINK_OFFSET
# - 202003/h8300-randconfig-a001-20200327:CONFIG_BOOT_LINK_OFFSET= # false
# - 202003/sh-randconfig-a001-20200313:CONFIG_BOOT_LINK_OFFSET=0x00800000 # true
#
# is_config_enabled CONFIG_BOOT_LINK_OFFSET=
# - 202003/h8300-randconfig-a001-20200327:CONFIG_BOOT_LINK_OFFSET= # true
# - 202003/sh-randconfig-a001-20200313:CONFIG_BOOT_LINK_OFFSET=0x00800000 # true
is_config_enabled()
{
	local config="$1"
	local config_file

	[[ $config ]] || return

	if [[ $2 ]]; then
		config_file="$2"
	elif [[ -s .config ]]; then
		config_file=.config
	elif [[ $KBUILD_OUTPUT ]] && [[ -s $KBUILD_OUTPUT/.config ]]; then
		config_file=$KBUILD_OUTPUT/.config
	elif [[ $BUILD_PATH ]] && [[ -s $BUILD_PATH/.config ]]; then
		config_file=$BUILD_PATH/.config
	elif [[ $BUILD_DIR ]] && [[ -s $BUILD_DIR/.config ]]; then
		config_file=$BUILD_DIR/.config
	else
		return 2 # ENOENT
	fi

	# $ echo "CONFIG_CPU_BIG_ENDIAN=y" | grep "^CONFIG_CPU_BIG_ENDIAN=[^n]"; echo $?
	# CONFIG_CPU_BIG_ENDIAN=y
	# 0
	# $ echo "CONFIG_CPU_BIG_ENDIAN=n" | grep "^CONFIG_CPU_BIG_ENDIAN=[^n]"; echo $?
	# 1
	[[ $config == *"="* ]] || config+='=[^n]'
	grep -q "^$config" "$config_file"
}

setup_cross_vars()
{
	case $ARCH in
		arm)
			cross_pkg=arm-linux-gnueabi
			# cross_gcc=arm-linux-gnueabihf-gcc
			crosstool=arm-linux-gnueabi
			;;
		arm64)
			cross_pkg=aarch64-linux-gnu
			crosstool=aarch64-linux
			;;
		mips)
			if is_config_enabled CONFIG_64BIT; then
				cross_pkg=mips64-linux-gnuabi64
				crosstool=mips64-linux
			else
				cross_pkg=mips-linux-gnu
				crosstool=mips-linux
			fi
			;;
		powerpc|powerpc64)
			if is_config_enabled CONFIG_PPC64; then
				cross_pkg=powerpc64-linux-gnu
				crosstool=powerpc64-linux
			else
				cross_pkg=powerpc-linux-gnu
				crosstool=powerpc-linux
			fi
			;;
		sh)
			cross_pkg=sh4-linux-gnu
			crosstool=sh4-linux
			;;
		alpha)
			cross_pkg=alpha-linux-gnu
			crosstool=alpha-linux
			;;
		sparc64)
			cross_pkg=sparc64-linux-gnu
			crosstool=sparc64-linux
			;;
		sparc)
			if is_config_enabled CONFIG_64BIT; then
				cross_pkg=sparc64-linux-gnu
				crosstool=sparc64-linux
			else
				crosstool=sparc-linux
			fi
			;;
		parisc)
			if is_config_enabled CONFIG_64BIT; then
				cross_pkg=hppa64-linux-gnu
				crosstool=hppa64-linux
			else
				cross_pkg=hppa-linux-gnu
				crosstool=hppa-linux
			fi
			;;
		parisc64)
			cross_pkg=hppa64-linux-gnu
			crosstool=hppa64-linux
			;;
		openrisc)
			crosstool=or1k-linux
			;;
		s390)
			cross_pkg=s390x-linux-gnu
			crosstool=s390-linux
			;;
		m68k)
			cross_pkg=m68k-linux-gnu
			crosstool=m68k-linux
			;;
		c6x)
			crosstool=c6x-elf
			;;
		riscv)
			if is_config_enabled CONFIG_64BIT; then
				cross_pkg=riscv64-linux-gnu
				crosstool=riscv64-linux
			elif is_config_enabled CONFIG_32BIT; then
				crosstool=riscv32-linux
			else
				cross_pkg=riscv64-linux-gnu
				crosstool=riscv64-linux
			fi
			;;
		loongarch)
			crosstool=loongarch64-linux
			;;
		*)
			# arc, xtensa
			crosstool=$ARCH-linux
			;;
	esac
}

# usage:
#   is_kernel_version "<=" 5.16
#   is_kernel_version "==" 6.0
is_kernel_version()
{
	local operator=$1
	local other=$2

	warn_empty "$operator" || return
	warn_empty "$other" || return

	warn_empty "$kernel_version_major" || return
	warn_empty "$kernel_version_minor" || return

	local other_kernel_version_major=${other%.*}
	local other_kernel_version_minor=${other#*.}

	(( (kernel_version_major * 100 + kernel_version_minor) $operator (other_kernel_version_major * 100 + other_kernel_version_minor) ))
}
