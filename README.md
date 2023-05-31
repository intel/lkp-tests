# Linux Kernel Performance tests

## Getting started

```
	git clone https://github.com/intel/lkp-tests.git

	cd lkp-tests
	make install

	lkp help
```

## Install dependency packages for jobs

```
	# browse and select a job you want to run, for example, jobs/hackbench.yaml
	ls lkp-tests/jobs
	
	# install the common dependencies for lkp
	# Note: lkp doesn't support ruby >= 3.0, default ruby version should be 2.x
	lkp install
```

## Run one atomic job

```
	lkp split-job lkp-tests/jobs/hackbench.yaml
	# output is:
	# jobs/hackbench.yaml => ./hackbench-1600%-process-pipe.yaml
	# jobs/hackbench.yaml => ./hackbench-1600%-process-socket.yaml
	# jobs/hackbench.yaml => ./hackbench-1600%-threads-pipe.yaml
	# jobs/hackbench.yaml => ./hackbench-1600%-threads-socket.yaml
	# jobs/hackbench.yaml => ./hackbench-50%-process-pipe.yaml
	# jobs/hackbench.yaml => ./hackbench-50%-process-socket.yaml
	# jobs/hackbench.yaml => ./hackbench-50%-threads-pipe.yaml
	# jobs/hackbench.yaml => ./hackbench-50%-threads-socket.yaml

	# install the remaining dependencies for the splited job
	lkp install ./hackbench-50%-threads-socket.yaml
	# or add -f option to force to install all dependencies
	lkp install -f ./hackbench-50%-threads-socket.yaml

	lkp run ./hackbench-50%-threads-socket.yaml
```

## Run your own disk partitions

Specify disk partitions by defining hdd_partitions/sdd_partitions in host file
named with local hostname and then lkp split-job will write the disk partitions
information to split job file automatically.

Please note that disk partitions may be formatted/corrupted to run job.

```
	echo "hdd_partitions: /dev/sda /dev/sdb" >> lkp-tests/hosts/$(hostname | sed -r 's/-[0-9]+$//g' | sed -r 's/-[0-9]+-/-/g')
	lkp split-job lkp-tests/jobs/blogbench.yaml
	# output is:
	# lkp-tests/jobs/blogbench.yaml => ./blogbench-1HDD-ext4.yaml
	# lkp-tests/jobs/blogbench.yaml => ./blogbench-1HDD-xfs.yaml
	# ...
	lkp install ./blogbench-1HDD-ext4.yaml
	lkp run ./blogbench-1HDD-ext4.yaml
```

## Run your own benchmarks

To run your own benchmarks that are not part of lkp-tests, you can use mytest job.

```
	lkp split-job lkp-tests/jobs/mytest.yaml
	# output is:
	# jobs/mytest.yaml => ./mytest-defaults.yaml
	lkp run ./mytest-defaults.yaml -- <command> <argument> ...
```

## Check result
```
	lkp result hackbench
```

## Add extra scripts in post run stage
```
	# create new scripts or rename hidden template scripts in the directory
	echo "echo result_root: \$RESULT_ROOT" > post-run/print-result-root
	lkp run ./ebizzy-10s-1x-200%.yaml
	# output is:
	# ...
	# result_root: /lkp/result/ebizzy/10s-1x-200%/shao2-debian/debian/defconfig/gcc-6/5.7.0-2-amd64/1
```

## Supported Distributions

Most test cases should install/run well in

- Debian sid
- Archlinux
- CentOS7

There is however some initial support for:

- OpenSUSE:
	- jobs/trinity.yaml
- Fedora
- Clear Linux(>=22640)

As for now, lkp-tests still needs to run as root.

## Adding distribution support

If you want to add support for your Linux distribution you will need
an installer file which allows us to install dependencies per job. For
examples look at: distro/installer/* files.

Since packages can have different names we provide an adaptation mapping for a
base Ubuntu package (since development started with that) to your own
distribution package name, for example adaptation files see:
distro/adaptation/*. For now adaptation files must have the architecture
dependent packages (ie, that ends with the postfix :i386) towards the end
of the adaptation file.

You will also want to add a case for your distribution on sync_distro_sources()
on the file lib/install.sh.

## Extra Documentation
Refer to https://github.com/intel/lkp-tests/wiki

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
