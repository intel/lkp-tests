# lkp-tests Documentation

Welcome to the documentation for lkp-tests, the Linux Kernel Performance (LKP)
test suite collection. This directory contains guides for writing tests,
running them locally, and troubleshooting common problems.

## Getting Started

For installing lkp-tests and running your first job, see the top-level
[README.md](../README.md).

## Guides

* **[Writing and Running Tests](writing-tests.md)** - How to write a new
  test case and run the test suite for the Linux kernel.
* **[How to Add Test Cases](add-testcase.md)** - Detailed walkthrough of
  adding a new benchmark (package script, test script, parser, and job
  file), using netperf as a worked example.
* **[Job File](job-file.md)** - Job YAML syntax: includes, ERB templates,
  multi-part job files, incremental hash updates, and script/variable
  resolution rules.
* **[How to Run a Local Monitor](run-local-monitor.md)** - Running monitor
  scripts in a minimal environment, with or without an accompanying
  benchmark.
* **[How to Kill Monitors and Daemons](kill-monitor-and-daemon.md)** - The
  three supported ways to stop monitors/daemons once a job finishes.

## Reference

* **[FAQ](faq.md)** - Frequently asked questions about the 0-Day/LKP
  project, installation troubleshooting, kbuild/boot/performance testing,
  and mailing list/git tree testing.

## Contributing

See the "Contributing" section of the top-level [README.md](../README.md)
for the pull request workflow, and [COPYING](../COPYING) for licensing.
