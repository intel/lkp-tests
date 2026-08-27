require 'spec_helper'
require 'json'
require 'open3'
require 'yaml'
require "#{LKP_SRC}/lib/lkp_path"

# Guards against the "quote everything" shell mistake: opt_* variables (and a
# few named option/count holders) carry whitespace-separated command options
# and MUST stay unquoted so the shell splits them into separate argv. Quoting
# them collapses an option list into one argument (e.g.
# "mkfs.ext4: invalid option -- ' '") or passes an empty '' argument when the
# holder is unset (e.g. "vmstat: failed to parse argument: ''"). Both make the
# tool fail while looking like a harmless quoting cleanup in review.
#
# WAIT_POST_TEST_CMD/WAIT_JOB_FINISHED_CMD (lib/wait.sh) are themselves
# two-word strings ("<path>/wait post-test"); quoting either one collapses
# them into a single argv entry too, so exec fails with
# "No such file or directory" instead of waiting for the test to finish.
#
# Unlike a line-based regex, this parses each file into a real shell AST
# (via `shfmt --to-json`, the mvdan.cc/sh parser already required by `rake
# shfmt`/`lkp-lint`) and only inspects CallExpr.Args -- a command's actual
# argv words. That structurally rules out comments, heredoc bodies, and
# assignments (which parse as CallExpr.Assigns, a different field) without
# any hand-rolled skip/assign regex, and correctly follows multi-line
# commands and nested substitutions the way the shell itself would.
#
# Known limitation: this only checks NAMED variables. A multi-word value
# forwarded through a positional parameter (a function receiving it as
# "$1" and later quoting "$1" itself in a command position) is not
# caught -- adding "$1"/"$2"/... to the checked list would false-positive
# on the very common, legitimate "forward my own args" idiom everywhere.
#
# A `# shellcheck disable=...SC2086...` comment marks a statement where a
# variable is deliberately meant to word-split, but was tried and reverted
# as a detection signal: real statements like programs/cpu2006/run's
# multi-line `runspec $opt_numa ... --define "$topo" ... -n "$iterations"
# "$test_name"` carry that comment for one variable ($opt_numa, already
# named) while quoting several OTHER, unrelated variables correctly in the
# same statement -- flagging every quote in an SC2086-disabled statement
# false-positives on exactly that shape. Add newly discovered word-split
# variables to the named list below instead.
module OptionListQuotingAst
  module_function

  # a Word node's sole content is a plain literal, e.g. a command name
  def literal_value(word)
    parts = word && word['Parts']
    return nil unless parts && parts.length == 1 && parts[0]['Type'] == 'Lit'

    parts[0]['Value']
  end

  # a Word node's sole content is "$name"/"${name}" for one of the named vars
  def quoted_named_var(word, named)
    parts = word['Parts'] || []
    return nil unless parts.length == 1 && parts[0]['Type'] == 'DblQuoted'

    inner = parts[0]['Parts'] || []
    return nil unless inner.length == 1 && inner[0]['Type'] == 'ParamExp'
    return nil if inner[0]['Index'] # "${arr[@]}"/"${arr[i]}" is the correct array idiom

    value = inner[0].dig('Param', 'Value')
    value if value && value =~ named
  end

  def each_call_expr(node, &block)
    case node
    when Hash
      yield node if node['Type'] == 'CallExpr'
      node.each_value { |v| each_call_expr(v, &block) }
    when Array
      node.each { |v| each_call_expr(v, &block) }
    end
  end

  def offenders_in(tree, named, allow_commands)
    offenders = []

    each_call_expr(tree) do |call|
      args = call['Args'] || []
      next if args.empty?

      # a literal command name (e.g. "echo") makes quoting its arguments
      # safe; a dynamic/quoted command name (Args[0] itself a named var,
      # e.g. `"$WAIT_POST_TEST_CMD" "$@"`) is not, and must still be checked
      cmd_name = literal_value(args[0])
      next if cmd_name && allow_commands.include?(cmd_name)

      args.each do |arg|
        var = quoted_named_var(arg, named)
        next unless var

        offenders << [arg.dig('Pos', 'Line'), var]
      end
    end

    offenders
  end
end

# A checker that never fires is indistinguishable from a broken one as long
# as the codebase it scans happens to be clean -- these fixtures give
# OptionListQuotingAst known-bad and known-good input on every run, so a
# future change that silently turns the check into a no-op (a broken
# shfmt invocation, a typo'd Type string, an inverted condition) fails here
# immediately instead of waiting for someone to reintroduce a real bug.
describe 'OptionListQuotingAst (self-test)' do
  named = /\Aopt_foo\z/
  allow_commands = %w(echo).freeze

  def offenders_for(source, named, allow_commands)
    json, status = Open3.capture2('shfmt', '-ln=bash', '--to-json', stdin_data: source)
    raise "shfmt failed to parse fixture:\n#{source}" unless status.success?

    OptionListQuotingAst.offenders_in(JSON.parse(json), named, allow_commands)
  end

  it 'flags a quoted option-list variable in a real command argument' do
    offenders = offenders_for(<<~SH, named, allow_commands)
      opt_foo="-a -b"
      mkfs.ext4 "$opt_foo" /dev/sda1
    SH

    expect(offenders).to eq([[2, 'opt_foo']])
  end

  it 'flags a quoted option-list variable used as the command itself' do
    offenders = offenders_for(<<~SH, named, allow_commands)
      opt_foo="cmd arg"
      "$opt_foo" more
    SH

    expect(offenders).to eq([[2, 'opt_foo']])
  end

  it 'does not flag the correct unquoted form' do
    offenders = offenders_for(<<~SH, named, allow_commands)
      opt_foo="-a -b"
      mkfs.ext4 $opt_foo /dev/sda1
    SH

    expect(offenders).to be_empty
  end

  it 'does not flag a plain assignment (Assigns, not Args)' do
    offenders = offenders_for("opt_foo=\"-a -b\"\n", named, allow_commands)

    expect(offenders).to be_empty
  end

  it 'does not flag an allowlisted command formatting its own output' do
    offenders = offenders_for(<<~SH, named, allow_commands)
      opt_foo="-a -b"
      echo "$opt_foo"
    SH

    expect(offenders).to be_empty
  end

  it 'does not flag a quoted bash array (the correct array idiom)' do
    offenders = offenders_for(<<~SH, named, allow_commands)
      opt_foo=(-a -b)
      cmd "${opt_foo[@]}"
    SH

    expect(offenders).to be_empty
  end
end

describe 'option-list variable quoting' do
  # variables that hold word-split option/argument lists
  named = /\Aopt_[A-Za-z0-9_]+\z|\A(?:opts|options|other_params|command|
           ensure_mkfs|def_mkfs|def_mount|mount_option|mkfs|mount|
           count|disks|raid_device|ssd_partitions|hdd_partitions|
           WAIT_POST_TEST_CMD|WAIT_JOB_FINISHED_CMD)\z/x

  # commands where a quoted value is legitimate: the tool formats/tests it,
  # rather than word-splitting it back into separate arguments of its own
  allow_commands = %w(echo printf [ test).freeze

  # Deliberate exceptions: the quoted var's whole multi-word value is passed
  # as ONE positional argument to a locally-defined shell function, not
  # exec'd directly -- the function's own body expands it unquoted instead.
  safe_quoted_uses = {
    'programs/energy/monitor' => ['WAIT_POST_TEST_CMD']
  }.freeze

  # Known shfmt (v3.10.0) parser limitations, confirmed as valid bash via
  # `bash -n` -- not a defect in the script itself. Read from lkp-core's
  # etc/ file (this repo has none of its own yet, hence the ENOENT rescue)
  # so `rake shfmt` and this check share one list instead of two.
  unparseable_by_shfmt = begin
    YAML.load_file(LKP::Path.src('etc/shfmt-unparseable.yml'))
  rescue Errno::ENOENT
    {}
  end.freeze

  files = Dir.glob("#{LKP_SRC}/programs/**/*") + Dir.glob("#{LKP_SRC}/lib/**/*.sh")
  files = files.select do |f|
    next false unless File.file?(f) && !File.symlink?(f)

    head = begin
      File.open(f, &:readline).scrub
    rescue StandardError
      ''
    end
    head =~ %r{\A#!.*sh\b}
  end

  if system('which shfmt >/dev/null 2>&1')
    files.each do |file_path|
      relative_path = file_path.sub("#{LKP_SRC}/", '')

      describe relative_path do
        if unparseable_by_shfmt.key?(relative_path)
          it 'is skipped (known shfmt parser limitation)' do
            skip "shfmt cannot parse this file: #{unparseable_by_shfmt[relative_path]}"
          end
        else
          it 'does not quote word-split option/count variables' do
            json, status = Open3.capture2('shfmt', '-ln=bash', '--to-json', stdin_data: File.read(file_path))

            expect(status).to be_success, "shfmt failed to parse #{relative_path}"

            exceptions = safe_quoted_uses[relative_path] || []
            offenders = OptionListQuotingAst.offenders_in(JSON.parse(json), named, allow_commands)
                                            .reject { |_line, var| exceptions.include?(var) }
                                            .map { |line, var| "#{line}: #{var}" }

            expect(offenders).to be_empty,
                                 'quoted option/count variables must be left unquoted so the ' \
                                 "shell word-splits them:\n  #{offenders.join("\n  ")}"
          end
        end
      end
    end
  else
    it 'skips option-list quoting checks (shfmt not installed)' do
      skip 'shfmt not installed'
    end
  end
end
