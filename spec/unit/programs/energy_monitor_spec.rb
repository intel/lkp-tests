require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require "#{LKP_SRC}/lib/bash"

describe 'programs/energy/monitor take_snapshot' do
  # option_list_quoting_spec.rb statically exempts
  # `take_snapshot "$WAIT_POST_TEST_CMD"` on the assumption that
  # take_snapshot's own body re-splits $1 unquoted (`-- $1`). This proves
  # that round trip actually holds against the real, current source,
  # instead of trusting the static exception alone.
  #
  # Runs the real, unmodified programs/energy/monitor end to end: LKP_SRC
  # is pointed at a temp root with the real lib/ symlinked in (so
  # lib/env.sh/debug.sh/wait.sh are the genuine files) plus a stub
  # bin/perf-events (avoids depending on a real perf and real energy
  # counters), and a stub `perf` placed first on PATH (env.sh's
  # set_perf_path falls back to resolving "perf" via PATH when
  # /lkp/benchmarks/perf/perf doesn't exist).
  it 'passes WAIT_POST_TEST_CMD to perf as two separate trailing argv words' do
    Dir.mktmpdir('energy-monitor-spec-') do |tmp|
      FileUtils.ln_s("#{LKP_SRC}/lib", "#{tmp}/lib")
      FileUtils.mkdir_p("#{tmp}/bin")
      File.write("#{tmp}/bin/perf-events", <<~STUB)
        #!/bin/sh
        echo power/energy-cores
      STUB
      FileUtils.chmod('+x', "#{tmp}/bin/perf-events")

      FileUtils.mkdir_p("#{tmp}/stubbin")
      File.write("#{tmp}/stubbin/perf", <<~STUB)
        #!/bin/sh
        printf '%s\\n' "$@" >#{tmp}/argv
      STUB
      FileUtils.chmod('+x', "#{tmp}/stubbin/perf")

      Bash.run(<<~SCRIPT)
        export TMP=#{tmp}
        export LKP_SRC=#{tmp}
        export PATH=#{tmp}/stubbin:$PATH
        bash #{LKP_SRC}/programs/energy/monitor
      SCRIPT

      argv = File.read("#{tmp}/argv").lines(chomp: true)
      # last two argv words are the two halves of WAIT_POST_TEST_CMD
      # ("$LKP_SRC/bin/event/wait" and "post-test") -- if the call site's
      # quoting regressed, they arrive merged as one word instead
      expect(argv.last(2)).to eq(["#{tmp}/bin/event/wait", 'post-test'])
    end
  end
end
