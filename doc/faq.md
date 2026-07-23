# 0day/LKP FAQ

[General](#general)
[Installation troubleshooting](#installation-troubleshooting)
[Kbuild tests](#kbuild-tests)
[Boot tests](#boot-tests)
[Performance tests](#performance-tests)
[LKML patch testing](#lkml-patch-testing)
[Git tree testing](#git-tree-testing)

## General

#### Q: Hello kernel test robot! Who are you, where are you from, what do you do?

Hello!

I'm first created by Tim Chen in the name "LKP", as Linux Kernel Performance
regression tracking is my first job. Then re-created by Fengguang Wu in the
name "0day", as my work is extended to build/boot testing and the focus is
shift-left to instantaneous testing on your bleeding edge code. Both my creators
are kernel developers experienced on performance optimizations, which defines
the genes and supreme end of my life: quality and performance.

I live in a warm home in Intel OTC Shanghai lab and now cared by the 0day/LKP
team led by Philip Li.

#### Q: What do you consume and produce?

	                           +------+
	                           |      | kbuild regression reports
	     mailing list patches  |      |---------------------------> YOU
	YOU ---------------------->|      |
	                           |  me  | boot regression reports
	                           |      |---------------------------> YOU
	          git pushes       |      |
	YOU ---------------------->|      | performance/power reports
	                           |      |---------------------------> YOU
	                           +------+


#### Q: What's your work flow?

A: Take me as public transportation (bus/train) rather than taxi.
I'm 7x24 busy running tests in some cyclic way. When you push new code
they'll be git-merged so as to jump in the restless test cycles ASAP.
When regressions are found, they'll be auto bisected and reported to
you -- once bisected, I can get your email address in commit changelog.

#### Q: What about weekend?

A: Sorry if my weekend reports disturb your happy time!
But you are not obliged to respond to a robot, especially if it's a
private report or tree.

#### Q: May I DoS you?

A: Feel free to push code as often as you need. I'll take care of the rest.
If a branch is pushed 2+ times between 2 bus arrivals, the last HEAD will be
picked up in the next bus (i.e. next test case to run). If your pushed HEAD
caused build/boot errors, it'll be shun by more time consuming runtime tests
and rejected in the next git merge until new/updated HEAD is pushed. So don't
be afraid that your frequent pushes may add burden to me, or push of broken
code may bring me down. I'm designed to digest bleeding edge code.

#### Q: How long the tests take?

The kbuild/boot tests may go on for over a week. The more comprehensive runtime
functional/performance test sets allocated to a given test box may take a month.

For kbuild tests, you can reasonably assume good coverage in 24 hours.
The first 1 hour roughly catches 60% regressions and the first 24 hours
will catch 90%.

For boot and runtime tests, expect days to weeks turn around time. The bisects
are time consuming if possible at all. A bisect may fail and be retried later.
Or it may have to wait long time to be bisected, since there are so many
changes detected!

If your tree has "notify_build_success_branch" configured, a build status report
will be send within 24 hours. If not sent in time, something is wrong and feel
free to notify us.

#### Q: How to contact you?

A: You may email to lkp@intel.com to reach all team members.

## Installation troubleshooting

#### Q: `sbin/split-job` (or any other command) fails with a Ruby syntax error, e.g. `unknown type of %string (SyntaxError)`

lkp-tests requires Ruby >= 3.1 (see the "Getting started" section in the
top-level [README.md](../README.md)). This error means the `ruby` on your
`$PATH` is too old to parse lkp-tests' syntax. Check your version:

```
$ ruby -v
```

If it reports something older than 3.1, install a newer Ruby using your
distribution's package manager or a version manager such as `rbenv` or
`rvm`, then make sure the new `ruby` takes precedence on `$PATH`.

#### Q: `lkp install` fails with `Unable to locate package <name>-dev`

Some distributions use different package name suffixes for development
packages (for example `libunwind-dev` vs `libunwind8-dev`). If a package
is not found, check `distro/depends/*` for the dependency declaration and
add/adjust the mapping for your distribution under `distro/adaptation/*`,
as described in the "Adding distribution support" section of the
top-level [README.md](../README.md).

## LKML patch testing

#### Q: What mailing lists do you monitor?

I subscribed to 30+ lists, you can check the listing under the mailing-list/
directory. Feel free to request for more inclusions.

#### Q: How to make sure the patch testing on a right base branch?

We suggest to use '--base' in `git format-patch` to provide the base tree info.
Without the base branch, we'll calculate a possible branch to apply the patch
which may cause the false positive, the introduction for '--base' can be found in
https://www.kernel.org/doc/html/latest/process/submitting-patches.html#providing-base-tree-information
or https://git-scm.com/docs/git-format-patch#_base_tree_information

#### Q: How can I test my patch in private?

A: You may git-send-email to patch-test@kernel.org (TODO: create the address).

## Git tree testing

#### Q: What git trees do you monitor?

There are 900+ git trees monitored. The full listing is in the repo/ directory.
Feel free to send us email or patch to add your git URL.

## Kbuild tests

#### Q: What's kbuild test coverage?

All major archs are build tested.
All arch/*/configs/* kconfigs are tested over time.
In addition, we keep generate new x86 randconfig kconfigs for build tests.
Static checks like sparse, smatch, coccinelle are run btw for several kconfigs.

## Boot tests

We run boot tests for a number of x86 static and randconfig kconfigs.
Patches passed kbuild/boot tests can move on to the more versatile and
time consuming runtime tests.

## Performance tests

#### Q: Can I add tests to your test farm?

Sure. Just send us patches for lkp-tests. Alternatively, you can add tests to
kernel selftests, perf bench, xfstests, phoronix, ltp, etc. test suites that's
integrated by lkp-tests.

#### Q: When do your test begin and finish?

What's behind your regression report for LKML patches?

The polling interval for all git servers except git.kernel.org is adaptive,
from minutes to dozens of minutes, depending on how often you do git pushes.

When started testing, 90% build errors can be caught in the first 24
hours. The build test will typically (unless your branch has errors or
is hard to merge with others) go on for days and runtime tests go on
for weeks for a given patch.

#### Q: I'd like to know the progress for my tests how can I add tests to your test farm?

The lkp@intel.com address has forwarding rules to all 0day/LKP team
members. 0day is our well known name, while LKP (Linux Kernel
Performance) is our Intel project name.

