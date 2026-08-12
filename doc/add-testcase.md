# How to Add Test Cases

In this document, we'll talk about how to add a test case to lkp-tests
for running.  We will take [netperf](http://www.netperf.org/netperf/)
as an example to illustrate all steps.  [netperf] is a benchmark tool
to measure various aspect of networking performance.


## What the test case does?

We need to learn three things in this step:

- ** how to run the test case **

  For example, we need know what kind of options it takes, how many
  sub testcases it supports, should we setup a special environment to
  be able to run it, and so on.  Normally speaking, we need to run it
  manually at least once so that we can know how to write a script to
  run it automatically.  This is a prepare step for writing the test
  script.

- ** major options **

  Usually a benchmark has many options. We may like to pick some of
  them as the job parameter so that we can try different value
  combination at job file to see how corresponding system reacts.
  This is a prepare step for writing the test script and job file.

- ** output **

  All testcases output must be converted to a layout, which will be
  described in later sections. Hence we need to know what the output
  looks like, and how to do the convert in a script.


Bear those three items in mind and now let's have a detailed look at
netperf.

Netperf is designed as a client-server model to test network bandwidth
between them.  In the sample, we assume the client and server running
on the same host.  Netperf has quite many tests defined, which falls
into two main categories: for measuring bulk data transfer performance
and request/response performance.

Now let's have a simple try first.

```
# start server first.
$ netserver
Starting netserver with host 'IN(6)ADDR_ANY' port '12865' and family AF_UNSPEC


# to run netperf test
$ netperf -t TCP_STREAM -c -C -l 10
MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to localhost () port 0 AF_INET
Recv   Send    Send                          Utilization       Service Demand
Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
Size   Size    Size     Time     Throughput  local    remote   local   remote
bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

 87380  16384  16384    10.00      38910.63   23.33    23.33    0.393   0.393
```

Here we use `TCP_STREAM` and limit the run time to 10 seconds.  It is
clear that `-t` and `-l` are two major options to netperf.  Well, just
like block size to IO test case, send size by option `-m` is key to
netperf, too.

```
$ netperf -t TCP_STREAM -c -C -l 10 -- -m 4096
MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to localhost () port 0 AF_INET
Recv   Send    Send                          Utilization       Service Demand
Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
Size   Size    Size     Time     Throughput  local    remote   local   remote
bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

 87380  16384   4096    10.00      33823.90   22.62    22.62    0.438   0.438


$ netperf -t TCP_STREAM -c -C -l 10 -- -m 1
MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to localhost () port 0 AF_INET
Recv   Send    Send                          Utilization       Service Demand
Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
Size   Size    Size     Time     Throughput  local    remote   local   remote
bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

 87380  16384      1    10.00        19.30   23.82    23.83    808.871  808.996
```

The result is totally different with different send size. Hence,
`send_size` is another major option we should care about.

With all the information we know, let's start to add a new test case.


## Test script

The script is to automate the steps we manually run the netperf
test. So, here it is:

```bash
#!/bin/sh
# - runtime
# - nr_threads
# - ip
# - test
# - send_size


export PATH=$BENCHMARK_ROOT/netperf/bin:$PATH

# start netserver
netserver

# load `sctp` module first if it's a SCTP related test
[[ $test == *"SCTP"* ]] && modprobe sctp 2>/dev/null
sleep 1

[[ "$send_size" ]] && test_options="-- -m $send_size"

```

Note that the five first comment lines are a MUST to lkp-tests.

```bash
# - runtime
# - nr_threads
# - ip
# - test
# - send_size
```

It explicitly tells that `runtime`, `nr_threads`, `ip`,`test` and
`send_size` are the parameters of this script. For any test case
needing paramter(s), need such comment lines and follow exactly the
same format `# - parameter`.


## Job file

Once we know what the test case does, and what kind of major options
they are, it's an easy task to write a job file.

```yaml
testcase: netperf

ip: ipv4

runtime: 300s
nr_threads:
- 200%
- 25%
- 1

netperf:
  test:
  - TCP_STREAM
  - TCP_MAERTS
  - TCP_SENDFILE
  - TCP_RR
  - TCP_CRR
  - UDP_RR
  - SCTP_RR
  - SCTP_STREAM
  - SCTP_STREAM_MANY
  send_size:
  - 1K
  - 4K
  - 1M
```


## Parse script

All result data has to be converted to a style of `key: value` format.

This is done by a script, and it should be located at
`programs/netperf/parse`.

Note that just like the test script at `programs/netperf/run`, the parse
script is also test case specific and it must follow below two rules:

- it has to be `key: value` format

  Note that the format has to be exactly the same: no extra space is
  allowed.

- value has to be a number

For example, the main netperf output is Throughput. Hence the job of
`programs/netperf/parse` is clear: extract the Throughput field and its
value out:

```bash
#!/bin/sh

throughput=$(tail -n 1 | awk '{print $5}')
echo "Throughput_Mbps: $throughput"
```

To check whether the script works right, use below commands

```bash
$ netperf -t TCP_STREAM -c -C -l 10 -- -m 1M | programs/netperf/parse
```

If the output is something like below `key: value` pairs, then the
script works right.

```bash
Throughput_Mbps: 54790.22
```

Note: Above script is a very simple script to help illustrate how to
write a parse script. The real `programs/netperf/parse` script is much
more complex than above, as the output layout is different for
measuring bulk data transfer performance and measuring
request/response performance. And the real test also supports
multiprocess of netperf client.


## Package netperf

This step is to generate a netperf package in case there is no netperf
installed in the test OS.  The package includes all information that
we need to run netperf benchmarks, such as netserver and netperf
binaries.

The method used to install additional packages is using the makepkg
from Arch Linux, which is a script to automate the building of
packages. A script named PKGBUILD is needed to use this script.
PKGBUILD files of some packages can be download from
[AUR](https://aur.archlinux.org/).

Below is a sample. It downloads the source code and build it. And the
makepkg system will generate the package.

```bash
pkgname=netperf
pkgver=2.7.0
pkgrel=0
arch=('i686' 'x86_64')
source=("https://fossies.org/linux/misc/netperf-$pkgver.tar.gz")
md5sums=('96e38fcb4ad17770b291bfe58b35e13b')

build()
{
    cd "$srcdir/$pkgname-$pkgver"
    cp /usr/share/misc/config.{guess,sub} .
    ./configure $CONFIGURE_FLAGS
    make
}

package() {
    cd "$srcdir/$pkgname-$pkgver"
    make DESTDIR="$pkgdir/" install
}

```

## Add dependencies

The installation of package netperf may depends on some packages.
To have these depends installed first, add these names to the files:

	programs/netperf/pkg/depends
	programs/netperf/pkg/depends-dev

The file `depends` lists the packages needed to run the netperf test, and
`depends-dev` lists the development packages needed to build netperf.

Theses packages could be provided by distribution or built by makepkg.
The package names on Debian are used as the base and they will be
adapted for other distributions and makepkg.

for example on Debian

```
libsctp-dev
gcc-4.9
```

If on different distributions the dependency names are different, for
example on Debian it is $pkgname but on the distribution $distro it is
$adapted_pkg, then add the line to the file distro/adaptation/$distro:

```
$pkgname: $adapted_pkgname
```

To install netperf with the PKGBUILD on desired distribution $distro,
add the package name to the distro/adaptation-pkg/$distro:

```
netperf::
```

If the package name installed by PKGBUILD is also needs to be adapted,
use this line instead:

```
netperf: $adapted_pkgname
```


## Example

Give an example to explain how to add one testcase, take hwsim as example:

1) add one PKGBUILD script and relevant dependency package config
	programs/hwsim/pkg/PKGBUILD
	programs/hwsim/pkg/depends
	programs/hwsim/pkg/depends-dev

   add the package adaptation "hwsim:: " to the adaptation-pkg files:
	distro/adaptation-pkg/$distribution

2) add one test script
	programs/hwsim/run

3) add one parse script
	programs/hwsim/parse

4) add one job file
	jobs/hwsim.yaml

5) add hwsim to the linux test cases list
	etc/linux-test-cases

6) commands to debug the new test case
	cd lkp-tests
	make install

	# install the common dependencies for lkp
	lkp install

	lkp split-job lkp-tests/jobs/hwsim.yaml
	# output is:
	# lkp-tests/jobs/hwsim.yaml => ./hwsim-hwsim-00.yaml

	# install the remaining dependencies for the splited job
	lkp install ./hwsim-hwsim-00.yaml
	# when second time run the command, the pkg will not build again,
	# to build the pkg again, you need add flag "-f", it may build
	# all monitors
	lkp install -f ./hwsim-hwsim-00.yaml
	# or you can run the following command, it only builds the test
	# case itself
	lkp install -f lkp-tests/programs/hwsim/run

	lkp run ./hwsim-hwsim-00.yaml

NOTE:

The test case run time should be about 300s~600s.


## How to add rspec tests for a new testcase parse script

RSpec is a unit test framework for the Ruby programming language. RSpec is a Behavior driven
development tool. Tests written in RSpec focus on the "behavior" of an application being tested.
RSpec does not put emphasis on, how the application works but instead on how it behaves, in other
words, what the application actually does.

In order to test the parse scripts under "lkp-tests/programs/*/parse", we've
created spec file `spec/unit/lib/stats_spec.rb`, we also need to create
example input file and expected output file under
"lkp-tests/spec/fixtures/stats/". Then run rspec test to check it's result.
If it's result not showing failure, that means the testcase parse script can
output result as examples expected.

An example to explain how to add rspec test for programs/mpstat/parse:

1. Check code programs/mpstat/parse, make it have a choice to get input data
   by calling argument `ARGV[0]` or variable `$stdin`. Such as the following
   lines from programs/mpstat/parse:
```ruby
    if ARGV[0]
      mpstat = ARGV[0]
    elsif ENV['RESULT_ROOT']
      RESULT_ROOT = ENV['RESULT_ROOT']
      mpstat = "#{RESULT_ROOT}/mpstat"
    end
```

2. Prepare file `1` and `1.yaml` under lkp-tests/spec/fixtures/stats/mpstat.

   File `lkp-tests/spec/fixtures/stats/mpstat/1` is typical raw data example
   that need to be handled by "programs/mpstat/parse" as input.

   File `lkp-tests/spec/fixtures/stats/mpstat/1.yaml` is the data output by
   executing "programs/mpstat/parse < 1". If the script has several types of
   raw data, then several example file pairs can be created, numbered in
   order, such as `1`/`1.yaml`, `2`/`2.yaml` in
   "lkp-tests/spec/fixtures/stats/mpstat".

3. Run rspec test by command:
```bash
    cd lkp-tests
    bundle exec rspec spec/unit/lib/stats_spec.rb -e "spec/fixtures/stats/mpstat"
```

4. Check rspec test result. If have any failure reported in results, then need to check
code "programs/mpstat/parse" and spec examples file under
"lkp-tests/spec/fixtures/stats/mpstat", and do some deep analysis.

   The following result indicate the rspec test is pass.
```
   Finished in 0.00821 seconds (files took 0.10604 seconds to load) 11 examples, 0 failures
```
