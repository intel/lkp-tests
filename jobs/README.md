# Job definition to execution


Job files are the basic unit of test description and execution.
They are written in [YAML](http://yaml.org/YAML_for_ruby.html) format.

The job YAML is extended and interpreted in the below ways.

## include/merge hash from an external file

YAML has a hash merge feature:

  http://yaml.org/type/merge.html

	<< : *REF

We make it a bit more convenient to support merging from external file, too.
If the job file contains a line

	<< : FILE

The hash contents of FILE will be merged into the current YAML location.

In the most fundamental form, a job YAML contains a hash table of key-values.
The keys fall into 2 main categories:

## ERB template

The following template tags are recognized

Expanded at job YAML load time:

	<% Ruby code -- inline with output %>
	<%= Ruby expression -- replace with result %>
	<%# comment -- ignored -- useful in testing %>
	% a line of Ruby code -- treated as <% line %>
	%% replaced with % if first thing on a line and % processing is used
	<%% or %%> -- replace with <% or %> respectively

Expanded during job matrix expansion:

	{{  Ruby expression -- replace with result }}
	{{ can.reference.variable.defined.in.same.job }}

Please do not overuse ERB templates: it's anti-intuitive and discouraged
to write complex ERB templates. WARNING: our code is designed to fail when
loading complex ERB templates.

## Multi-part job file

When the job file contains several YAML documents separated by "---",

	hash_0
	---
	hash_1
	---
	...
	---
	hash_N

they'll be split into hashes

	hash_0
	hash_0 + hash_1
	...
	hash_0 + hash_N

## Incremental Hash update

These top level hash keys

	a.b.c:
	a[.b.c]+:
	a[.b.c]-:

are for incremental revising the preceding part in 3 cases:

1) multi-part job: allows follow up parts to modify the base part
2) modify contents of the "<< :" included file
3) command line options to modify the job file

These top level keys are accumulative everywhere:

	mail_to
	mail_cc
	constraints
	need_*

## Scripts

If the key matches some script file in the below paths, it is treated as an
executable script.

  - $LKP_SRC/monitors
  - $LKP_SRC/programs

The mapping rules for scripts in `programs/` are:

  - `programs/<name>/setup`  => `setup` script
  - `programs/<name>/daemon` => `daemon` script
  - `programs/<name>/run`    => `test` script


## Variables

Otherwise if

  - the key is a valid keyword
  - the value is a string or an array of strings

They will be exported as environment variables.

`$LKP_SRC/sbin/job2sh` uses the above 2 main rules to convert a job YAML file
into an executable shell script. Here is a conceptual demo.

```
	job.yaml (by USER)             ===>     job.sh (by LKP)
	define environment & actions            compile into sh for execution
	~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	  testcase: ...                            export  testcase=...
	  testbox: ...                             export  testbox=...
	  kconfig: ...                             export  kconfig=...
	  commit: ...                              export  commit=...
	  rootfs: ...                              export  rootfs=...
	  test_param1: ...                         export  test_param1=...
	  test_param2: ...                         export  test_param2=...
	  ...                                      ...
	  setup_script1:                           $LKP_SRC/programs/setup_script1/setup
	  setup_script2:                           $LKP_SRC/programs/setup_script2/setup
	  test_script:                             $LKP_SRC/programs/test_script/run
```
## job allocation
[This page](README-job-allocation.html) talks about job allocation.
