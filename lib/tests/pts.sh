#!/bin/bash

. $LKP_SRC/lib/env.sh
. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/reproduce-log.sh

# ffmpeg only support max 64 threads
fixup_ffmpeg()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/ffmpeg
	if [ -z $(grep -w 'NUM_CPU_CORES=64' $target) ]; then
		sed "2a[ \$NUM_CPU_CORES -gt 64 ] && export NUM_CPU_CORES=64" -i "$target"
	fi
}

# add --allow-run-as-root to open-porous-media-1.3.1
fixup_open_porous_media()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/open-porous-media
	sed -i 's/nice mpirun -np/nice mpirun --allow-run-as-root -np/' "$target"
}

# produce big file to /opt/rootfs when test on cluster
fixup_blogbench()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/blogbench
	[ "$LKP_LOCAL_RUN" = "1" ] || sed -i "s,\$HOME,\/opt\/rootfs," "$target"
}

# 1. increase max startup time
# 2. we have no sixth option it should be third option, change $6 to $3
# 3. this subtest will produce big file to BASE_DIR, here produce file to $3/workfiles
#    At last, remove these files by rm $3/workfiles
fixup_startup_time()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/startuptime-run
	# shellcheck disable=SC2016
	sed -i 's,$6,$3,' "$target"
	# shellcheck disable=SC2016
	sed -i 's,BASE_DIR=$3,BASE_DIR=$3/workfiles,' "$target"
	sed -i "33ased -i 's,120,600,' comm_startup_lat.sh" "$target"
	# shellcheck disable=SC2016
	sed -i '37arm -r $3/workfiles' "$target"
}

# before test netperf, start netserver firstly
fixup_netperf()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/netperf
	sed -i "2a./src/netserver" "$target"
}

# before test iperf, start iperf server firstly
fixup_iperf()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/iperf
	sed -i "2a./iperf3 -s -p 12345 &" "$target"
	sed -i '5apkill iperf3' "$target"
}

# before test nuttcp, start nuttcp server firstly
fixup_nuttcp()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/nuttcp
	sed -i "2a./nuttcp-8.1.4 -S &" "$target"
	sed -i '5apkill nuttcp-8.1.4' "$target"
}

fixup_ior()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/ior
	sed -i 's/ \$@ / /g' "$target"
}

# fix issue: Bootup is not yet finished (org.freedesktop.systemd1.Manager.FinishTimestampMonotonic=0)
# before:
# out, err = subprocess.Popen(["systemd-analyze"], stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate(
# after:
# import time
# err = 'err'
# i = 1
# while (err != '' and i <= 200):
#     out, err = subprocess.Popen(["systemd-analyze"], stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate()
#     time.sleep(3)
#     i += 1
fixup_systemd_boot_total()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/systemd-analyze.py
	sed -i '2aimport time' "$target"
	sed -i "4aerr = 'err'" "$target"
	sed -i '5ai = 1' "$target"
	sed -i "6awhile (err != '' and i <= 200):" "$target"
	sed -i "8s,^,\    ," "$target"
	sed -i "8a\    time.sleep(3)" "$target"
	sed -i "9a\    i += 1" "$target"
}

# fix issue: Test Run-Time Too Short
# before:
# 141:                            $minimal_test_time = pts_config::read_user_config('PhoronixTestSuite/Options/TestResultValidation/MinimalTestTime', 2);
# after:
# 141:                            $minimal_test_time = 0;
fixup_sqlite()
{
	[ -n "$environment_directory" ] || return
	local target=/usr/share/phoronix-test-suite/pts-core/objects/pts_test_result_parser.php
	sed -i "s,pts_config::read_user_config('PhoronixTestSuite\/Options\/TestResultValidation\/MinimalTestTime'\, 2),0," "$target"
}

# force run times to avoid soft_timeout and auto-increase runs
force_times_to_run()
{
	if [[ $times_to_run ]]; then
		log_cmd export FORCE_TIMES_TO_RUN=$times_to_run
	else
		[[ -n "$environment_directory" ]] || return

		local target=${environment_directory}/../test-profiles/pts/${test}/test-definition.xml
		if [[ -f $target ]]; then
			local times_to_run=$(grep -oP '(?<=<TimesToRun>).*(?=</TimesToRun>)' $target)
			if [[ $times_to_run ]]; then
				log_cmd export FORCE_TIMES_TO_RUN=$times_to_run
			else
				log_cmd export FORCE_TIMES_TO_RUN=3
			fi
		else
			log_cmd export FORCE_TIMES_TO_RUN=3
		fi
	fi
}

# fix issue: [NOTICE] Undefined: min_result in pts_test_result_parser:478
fixup_smart()
{
	# root@lkp-csl-2sp8:~# less /usr/share/phoronix-test-suite/pts-core/pts-core.php | grep "pts_define('PTS_VERSION'"
	# pts_define('PTS_VERSION', '8.8.0');
	# phoronix_version=8
	phoronix_version=$(grep "pts_define('PTS_VERSION'" /usr/share/phoronix-test-suite/pts-core/pts-core.php | awk '{print $2}' | awk -F '' '{print $2}')
	# this issue has been fixed since v9.0.0
	local target="/usr/share/phoronix-test-suite/pts-core/objects/pts_test_result_parser.php"
	[ $phoronix_version -ge 9 ] || {
		sed -i "466a \                        \$min_result\ \=\ null;" "$target"
		sed -i "467a \                        \$max_result\ \=\ null;" "$target"
	}
}

# fix issue: libvo/vo_png.c:56:28: error: 'Z_NO_COMPRESSION' undeclared here (not in a function)
fixup_build_mplayer()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=$environment_directory/../test-profiles/pts/${test}/pre.sh
	sed -i 's/--disable-ivtv/--disable-ivtv --disable-png/' "$target"
}
# fix issue: chown: invalid user: 'mysql:mysql'
fixup_mysqlslap()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=$environment_directory/../test-profiles/pts/${test}/pre.sh

	sed -i '4a groupadd mysql' "$target"
	sed -i '5a useradd -g mysql mysql' "$target"
	sed -i '6a chown -R mysql:mysql data' "$target"
	sed -i '7a chown -R mysql:mysql .data' "$target"
}

# rebuild hpcc and add --allow-run-as-root to hpcc
# the test needs more than 2 hours
fixup_hpcc()
{
	[ -n "$environment_directory" ] || return

	local test=$1
	local mpdir="/usr/lib/x86_64-linux-gnu/openmpi"
	# check mpdir in Make file to make sure the test binary is built with right library
	[ -d "$mpdir" ] && [ "$(grep MPdir ${environment_directory}/pts/${test}/hpcc-*/hpl/Make.pts | awk '{print $NF}')" != "$mpdir" ] && {
		export MPI_PATH=$mpdir
		export MPI_INCLUDE=$mpdir/include
		export MPI_LIBS=$mpdir/lib/libmpi.so
		export MPI_CC=/usr/bin/mpicc.openmpi
		export MPI_VERSION=`$MPI_CC -showme:version 2>&1 | grep MPI | cut -d "(" -f1  | cut -d ":" -f2`
		phoronix-test-suite force-install pts/$test
	}

	local target=${environment_directory}/pts/${test}/hpcc
	sed -i 's/mpirun -np/mpirun --allow-run-as-root -np/' "$target"
}

# add --allow-run-as-root to lammps
# fix issue: There are not enough slots available in the system
fixup_lammps()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/lammps
	sed -i 's/mpirun -np/mpirun --allow-run-as-root --oversubscribe -np/' "$target"
}

# add --allow-run-as-root to npb
fixup_npb()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/npb
	sed -i 's/mpiexec -np/mpiexec --allow-run-as-root -np/' "$target"
}

# fix issue: sed: -e expression #1, char 16: unterminated `s' command
fixup_aom_av1()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/aom-av1
	sed -i "s,sed $'s,sed 's,g" "$target"
}

# default to test 1m
fixup_fio()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/fio-run

	# create virtual disk
	local test_disk="/tmp/test_fio.img"
	local test_dir="/media/test_fio"
	fallocate -l 10G $test_disk || return
	mkfs -t ext4 $test_disk 2> /dev/null || return
	mkdir -p $test_dir || return
	modprobe loop || return
	mount -t auto -o loop $test_disk $test_dir ||return

	sed -i 's,#!/bin/sh,#!/bin/dash,' "$target"
	sed -i "s#filename=\$DIRECTORY_TO_TEST#filename=$test_dir/fiofile#" "$target"

	# Choose
	# 1: Sequential Write
	# 2: Libaio
	# 3: Test All Options
	# 4: Test All Options
	# 5: 1MB
	# 6: Default Test Directory
	# 7: Test All Options
	test_opt="\n4\n3\n3\n3\n9\n1\n3\nn"
}

# change to use bash to gpu-residency
fixup_gpu_residency()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/gpu-residency
	sed -i 's,#!/bin/sh,#!/bin/bash,' "$target"
}

# change to use dash to bullet
fixup_bullet()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/bullet
	sed -i 's,#!/bin/sh,#!/bin/dash,' "$target"
}

# add bookpath option
fixup_crafty()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/crafty
	sed -i 's,crafty $@,crafty bookpath=/usr/share/crafty/ $@,' "$target"
}

fixup_gluxmark()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/$test
	export LD_LIBRARY_PATH=${target}/gluxMark2.2_src/libs
	export MESA_GL_VERSION_OVERRIDE=3.0
	export DISPLAY=:0
	# Choose
	# 1: Windowed
	# 2: Fill-Rate
	test_opt="\n2\n1\nn"
}

fixup_java_gradle_perf()
{
	local javapath=$(readlink -f $(which java) | awk -F/bin '{print $1}')
	[ -z "$javapath" ] && echo "ERROR: NO avaliable JAVA_HOME" >&2 && return 1
	export JAVA_HOME="$javapath"
}

fixup_systester()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/../test-profiles/pts/${test}/results-definition.xml
	[ -f $target.bak ] || cp $target $target.bak
	sed -i '/LineBeforeHint/d' $target
	export TOTAL_LOOP_TIME=1
	export TOTAL_LOOP_COUNT=1
}

fixup_java_jmh()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/../test-profiles/pts/${test}/results-definition.xml
	[ -f $target.bak ] || cp $target $target.bak
	sed -i 's,200, 25,' $target
}

fixup_network_loopback()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/network-loopback

	sed -i 's,nc -d -l,nc -l -p,' $target
}

fixup_mcperf()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/pts/${test}/mcperf
	sed -i 's#^./memcached -d -t#./memcached -d -u root -t#' $target
}

setup_python2()
{
	python -V 2>&1 | grep -q "^Python 2" && return
	ln -sf $(which python2) $(which python) || return
	ln -sf $(which pip2) $(which pip) || return
}

setup_python3()
{
	python -V 2>&1 | grep -q "^Python 3" && return
	ln -sf $(which python3) $(which python) || return
}

fixup_aom_av1_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i "3ased -i 's,64,300,' aom-20190916/aom_util/aom_thread.h" "$target"
}

fixup_ffmpeg_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i "6ased -i '4082,4083d' configure" "$target"
}

fixup_dolfyn_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i "4a sed -i \"s/stop'bug:/stop 'bug:/g\" gmsh2dolfyn.f90" "$target"
}

fixup_build_eigen_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i 's,\${CXX},\\${CXX},' "$target"
}

fixup_interbench()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/../test-profiles/pts/${test}/install.sh
	sed -i "4ased -i 's,interbench.read,/opt/rootfs/interbench.read,' interbench.c" "$target"
	sed -i "5ased -i 's,interbench.read,/opt/rootfs/interbench.read,' Makefile" "$target"
	sed -i "6ased -i 's,interbench.write,/opt/rootfs/interbench.write,' interbench.c" "$target"
	sed -i "7ased -i 's,interbench.write,/opt/rootfs/interbench.write,' Makefile" "$target"
	phoronix-test-suite force-install $test
}

# fix issue: Run out of memory under overlay/
# before:
# 106: $HOME/pg_/bin/initdb -D $HOME/pg_/data/db --encoding=SQL_ASCII --locale=C
# 109: PGDATA=\$HOME/pg_/data/db/
# after:
# 106: rm -rf /opt/rootfs/pg_
# 107: mkdir -p /opt/rootfs/pg_/data/db/
# 108: $HOME/pg_/bin/initdb -D /opt/rootfs/pg_/data/db/ --encoding=SQL_ASCII --locale=C
# 111: PGDATA=/opt/rootfs/pg_/data/db/
fixup_pgbench()
{
	[ -n "$environment_directory" ] || return
	local test=$1
	local target=${environment_directory}/../test-profiles/pts/${test}/install.sh
	sed -i "105a rm -rf /opt/rootfs/pg_" "$target"
	sed -i "106a mkdir -p /opt/rootfs/pg_/data/db/" "$target"
	sed -i 's,-D $HOME/pg_/data/db,-D /opt/rootfs/pg_/data/db/,' "$target"
	sed -i 's,PGDATA=\\$HOME/pg_/data/db/,PGDATA=/opt/rootfs/pg_/data/db/,' "$target"
	phoronix-test-suite force-install $test
}

fixup_xsbench_cl_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i "4ased -i '1048s,256,64,' XSBench_OCL.c" "$target"
}

fixup_clpeak_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i "4a sed -i '43a/usr/lib/x86_64-linux-gnu' CMakeLists.txt" "$target"
}

fixup_apache_siege_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i "31a mkdir \$HOME/.siege" "$target"
}

fixup_tesseract_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i 's,mv bench.so tesseract,mv bench.sh tesseract,' "$target"
}

fixup_gcrypt_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i '5a sed -i \"s,\\$(CPP) _\\$@,\\$(CPP) -P _\\$@,g\" src/Makefile*'  "$target"
	sed -i "15a sed -i \"s,define G10_MPI_INLINE_DECL  extern __inline__,define G10_MPI_INLINE_DECL  extern inline __attribute__ ((__gnu_inline__)),g\" mpi/mpi-inline.h" "$target"
}

fixup_lammps_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i '5a sed -i "s,-I/usr/lib/mpich/include/,-I/usr/lib/x86_64-linux-gnu/mpich/include/,g" MAKE/Makefile.debian Obj_debian/Makefile' "$target"
}

fixup_x264_opencl_install()
{
	local test=$1
	local target=/var/lib/phoronix-test-suite/test-profiles/pts/${test}/install.sh
	sed -i 's/\.\/configure --prefix=$HOME\/x264_\//\.\/configure --prefix=$HOME\/x264_\/ --enable-pic --enable-shared/g' "$target"
}

# exit when match option failed for 2 times
# before:
# 277                 $select = array();
# 278
# 279                 do
# 280                 {
# 281                         echo PHP_EOL;
# after:
# 277                 $select = array();
# 278                 $lkp_count = 1;
# 279
# 280                 do
# 281                 {
# 282                         if ($lkp_count > 2) {echo 'Wrong test option' . PHP_EOL;exit;}
# 283                         $lkp_count++;
# 284                         echo PHP_EOL;
patch_to_detect_wrong_test_option()
{
	local target=/usr/share/phoronix-test-suite/pts-core/objects/pts_user_io.php
	sed -i '/lkp_count/d' $target
	sed -i "277a \$lkp_count = 1;" "$target"
	sed -i "281a if (\$lkp_count > 2) {echo 'Wrong test option $test' . PHP_EOL; fwrite(STDERR, 'Wrong test option $test' . PHP_EOL); exit;}" "$target"
	sed -i "282a \$lkp_count++;" "$target"
}

fixup_install()
{
	local test=$1
	case $test in
	glmark2-*)
		# python2 is required for installing glmark2
		setup_python2
		;;
	cyclictest-*)
		# python2 is required for installing cyclictest
		setup_python2
		env | grep CFLAGS && unset CFLAGS
		;;
	memtier-benchmark-*)
		# fix issue: cc: error: x86_64: No such file or directory
		env | grep ARCH && unset ARCH
		;;
	clpeak-*)
		# fix issue: Could not find OpenCL include/libs.  Set OPENCL_ROOT to your OpenCL SDK.
		fixup_clpeak_install $test
		;;
	numenta-nab-*)
		# fix issue: No matching distribution found for nupic==1.0.5 (from nab==1.0)
		setup_python2
		;;
	pymongo-inserts-*)
		# python3 is required for installing pymongo-inserts
		setup_python3
		;;
	dolfyn-*)
		# fix issue: Error: Blank required in STOP statement near (1)
		fixup_dolfyn_install $test || die "failed to fixup dolfyn install"
		;;
	ffmpeg-*)
		# fix issue: Unable to create temporary directory in /lkp/lkp/src/tmp
		fixup_ffmpeg_install $test || die "failed to fixup $test install"
		;;
	aom-av1-*)
		# fix issue: g_threads out of range [..MAX_NUM_THREADS]
		fixup_aom_av1_install $test || die "failed to fixup $test install"
		;;
	xsbench-cl-*)
		# fix issue: unionized_grid_search: failed to launch kernel with error -54
		fixup_xsbench_cl_install $test || die "failed to fixup $test install"
		;;
	tesseract-*)
		# fix issue: mv: cannot stat 'bench.so': No such file or directory
		fixup_tesseract_install $test || die "failed to fixup tesseract install"
		;;
	apache-siege-*)
		# fix issue: /var/lib/phoronix-test-suite/installed-tests/pts/apache-siege-1.0.4//.siege/siege.conf: No such file or directory
		fixup_apache_siege_install $test || die "failed to fixup apache-siege install"
		;;
	gcrypt-*)
		# fix issue: multiple definition of `_gcry_mpih_add'
		#	     mkerrcodes.h:133:5: error: expected expression before ',' token
		fixup_gcrypt_install $test || die "failed to fixup gcrypt install"
		;;
	lammps-*)
		# fix issue: pointers.h:24:10: fatal error: mpi.h: No such file or directory
		fixup_lammps_install $test || die "failed to fixup lammps install"
		;;
	build-eigen-*)
		# fix issue: ./build-eigen: line 8: -DEIGEN2_SUPPORT=: command not found
		fixup_build_eigen_install $test || die "failed to fixup $test install"
		;;
	x264-opencl-*)
		fixup_x264_opencl_install $test || die "failed to fixup x264-opencl install"
	esac
}

fixup_test()
{
	local test=$1

	case $test in
		systester-[0-9]*)
			# Choose
			# 1: Gauss-Legendre algorithm [Recommended.]
			# 1: 4 Million Digits [This Test could take a while to finish.]
			# 3: 4 threads [2+ Cores Recommended]
			# TODO: select different test according to testbox's hardware
			test_opt="\n1\n1\n3\nn"
			fixup_systester $test
			;;
		java-jmh-*)
			fixup_java_jmh $test
			;;
		iozone-*)
			# Choose
			# 1: 1MB
			# 2: 2GB
			# 3: Test All Options
			test_opt="\n3\n2\n3\nn"
			;;
		interbench-*)
			# Choose
			# 1: Video
			# 2: Burn
			test_opt="\n4\n6\nn"

			# produce big file to /opt/rootfs when test on cluster
			[ "$LKP_LOCAL_RUN" = "1" ] || fixup_interbench $test
			;;
		numenta-nab-*)
			# fix issue: SyntaxError: Missing parentheses in call to 'print'.
			setup_python2
			;;
		mandel*gpu-*)
			# Choose
			# 2. GPU
			test_opt="\n2\nn"
			;;
		smallpt-gpu-*)
			# Choose
			# 2: GPU
			# 1: Complex
			test_opt="\n2\n1\nn"
			;;
		juliagpu-*)
			# Choose
			# 2: GPU
			test_opt="\n2\nn"
			;;
		luxmark-*)
			# Choose
			# 2: GPU
			# 3: Hotel
			test_opt="\n2\n3\nn"
			;;
		x11perf-*)
			# Choose
			# 1: 500px PutImage Square
			test_opt="\n1\nn"
			export DISPLAY=:0
			;;
		tesseract-*)
			export DISPLAY=:0
			;;
		smart-*)
			# Choose 1st disk to get smart info
			# 1: /dev/sda
			test_opt="\n1\nn"
			fixup_smart
			;;
		urbanterror-*)
			export DISPLAY=:0
			;;
		hdparm-read-*)
			# Choose
			# 1: /dev/sda
			test_opt="\n1\nn"
			;;
		plaidml-*)
			# Choose
			# 1: No
			# 2: Inference
			# 3: Mobilenet
			# 4: OpenCL
			test_opt="\n2\n2\n1\n2\nn"
			export DISPLAY=:0
			;;
		video-cpu-usage-*)
			# Choose
			# 1: OS X CoreVideo
			test_opt="\n5\na\nb\nc\nn"
			export DISPLAY=:0
			;;
		netperf-*)
			fixup_netperf $test
			;;
		startup-time-*)
			fixup_startup_time $test
			;;
		ior-*)
			fixup_ior $test
			;;
		iperf-*)
			fixup_iperf $test
			;;
		nuttcp-*)
			fixup_nuttcp $test
			;;
		sqlite-[0-9]*)
			fixup_sqlite $test
			;;
		blogbench-*)
			fixup_blogbench $test
			;;
		systemd-boot-total-*)
			# Choose
			# 1: Total 2: Userspace 3: Kernel
			test_opt="\n1,2,3\nn"
			fixup_systemd_boot_total $test
			;;
		mcperf-*)
			fixup_mcperf $test
			;;
		network-loopback-*)
			fixup_network_loopback $test
			;;
		build-mplayer-*)
			fixup_build_mplayer $test
			;;
		mysqlslap-*)
			fixup_mysqlslap $test
			;;
		ffmpeg-*)
			fixup_ffmpeg $test
			;;
		lammps-*)
			fixup_lammps $test
			;;
		npb-*)
			fixup_npb $test
			;;
		aom-av1-*)
			fixup_aom_av1 $test
			;;
		bullet-*)
			fixup_bullet $test
			;;
		gpu-residency-*)
			fixup_gpu_residency $test
			;;
		fio-*)
			fixup_fio $test
			;;
		hpcc-*)
			fixup_hpcc $test
			;;
		open-porous-media-*)
			fixup_open_porous_media $test
			;;
		crafty-*)
			fixup_crafty $test
			;;
		gluxmark-*)
			fixup_gluxmark $test
			;;
		java-gradle-perf-*)
			fixup_java_gradle_perf
			;;
		unigine-heaven-*|unigine-valley-*)
			export DISPLAY=:0
			;;
		glmark2-*|openarena-*|gputest-*|supertuxkart-*)
			export DISPLAY=:0
			;;
		clpeak-*)
			# 7: Kernel Latency
			# 4: Integer Compute INT # this subtest was disabled on Intel platform
			test_opt="\n7\nn"
			;;
		pgbench-*)
			fixup_pgbench $test
			;;
	esac
}

setup_run_option()
{
	run_option="run"
	if [[ "$debug" = 1 ]]; then
		run_option="debug-run"
	elif [[ "$debug" = 2 ]]; then
		run_option="default-run"
		test_opt=
	fi
}

run_test()
{
	local test=$1
	[ -n "$test" ] || die "testname is empty"

	force_times_to_run $test || die "failed to force times to run of $test"
	fixup_test $test || die die "failed to fixup $test"

	export PTS_SILENT_MODE=1
	echo PTS_SILENT_MODE=$PTS_SILENT_MODE

	patch_to_detect_wrong_test_option
	if [ -n "$option_a" ]; then
		test_opt=''
		for i in {a..j}
		do
			eval option=\$option_${i}
			[ -n "$option" ] || break
			test_opt="$test_opt$option\n"
		done
		# don't save test results when met:
		# Would you like to save these test results (Y/n):
		test_opt=${test_opt}n
	fi

	[ "$test_opt" ] && echo "test_opt: $test_opt"

	root_access="/usr/share/phoronix-test-suite/pts-core/static/root-access.sh"
	[ -f "$root_access" ] || die "$root_access not exist"
	sed -i 's,#!/bin/sh,#!/bin/dash,' $root_access

	phoronix-test-suite list-installed-tests | grep -q $test || die "$test is not installed"

	setup_run_option

	if echo "$test" | grep idle-power-usage; then
		# Choose
		# sleep 1 min
		# Enter Value: 1
		/usr/bin/expect <<-EOF
			spawn phoronix-test-suite $run_option $test
			expect {
				"Enter Value:" { send "1\\r"; exp_continue }
				"Would you like to save these test results" { send "n\\r"; exp_continue }
				eof { }
				default { exp_continue }
			}
		EOF
	elif echo "$test" | grep ethr; then
		# Choose
		# Server Address
		# Enter Value: localhost
		# 3: HTTP
		# 1: Bandwidth
		# 1: 1
		/usr/bin/expect <<-EOF
			spawn phoronix-test-suite $run_option $test
			expect {
				"Enter Value:" { send "localhost\\r"; exp_continue }
				"Protocol:" { send "3\r"; exp_continue }
				"Test:" { send "1\r"; exp_continue }
				"Threads:" { send "1\r"; exp_continue }
				"Would you like to save these test results" { send "n\\r"; exp_continue }
				eof { }
				default { exp_continue }
			}
		EOF
	elif echo $test | grep netperf; then
		# Choose
		# Enter Value: localhost
		# 5: UDP Request Response
		# 1: 10 Seconds
		/usr/bin/expect <<-EOF
			spawn phoronix-test-suite $run_option $test
			expect {
				"Enter Value:" { send "localhost\r"; exp_continue }
				"Test:" { send "5\r"; exp_continue }
				"Duration:" { send "1\r"; exp_continue }
				"Would you like to save these test results" { send "n\r"; exp_continue }
				eof { }
				default { exp_continue }
			}
		EOF
	elif echo $test | grep iperf; then
		# Choose
		# Enter Value: localhost
		# Enter Value: 12345
		# 1: 10 Seconds
		# 2: UDP
		# 1: 1
		/usr/bin/expect <<-EOF
			spawn phoronix-test-suite $run_option $test
			expect {
				"Enter Value:" { send "localhost\r12345\r"; exp_continue }
				"Duration:" { send "1\r"; exp_continue }
				"Test:" { send "2\r"; exp_continue }
				"Parallel:" { send "1\r"; exp_continue }
				"Would you like to save these test results" { send "n\r"; exp_continue }
				eof { }
				default { exp_continue }
			}
		EOF
	elif echo $test | grep nuttcp; then
		# Choose
		# 4: Test All Options
		# Enter Value: 127.0.0.1
		/usr/bin/expect <<-EOF
			spawn phoronix-test-suite $run_option $test
			expect {
				"Test:" { send "4\r"; exp_continue }
				"Enter Value:" { send "127.0.0.1\r"; exp_continue }
				"Would you like to save these test results" { send "n\r"; exp_continue }
				eof { }
				default { exp_continue }
			}
		EOF
	elif [ "$test_opt" ]; then
		echo -e "$test_opt" | log_cmd phoronix-test-suite $run_option $test
	else
		echo -e "n" | log_cmd phoronix-test-suite $run_option $test
	fi
}
