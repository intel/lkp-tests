#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'shellwords'
require "#{LKP_SRC}/lib/job"
require "#{LKP_SRC}/lib/lkp_path"

TMP ||= ENV['TMP'] || '/tmp'

SHELL_BLOCK_KEYWORDS = {
  'if' => %w[then fi],
  'for' => %w[do done],
  'while' => %w[do done],
  'until' => %w[do done],
  'function' => ['{', '}']
}.freeze

def valid_shell_variable?(key)
  key =~ /^[a-zA-Z_]+[a-zA-Z0-9_]*$/
end

def shell_encode_keyword(key)
  key.gsub(/[^a-zA-Z0-9_]/) { |m| "_#{m.getbyte(0)}_" }
end

def shell_escape_expand(val)
  val = val.join "\n" if val.is_a?(Array)

  case val
  when nil, ''
    ''
  when Integer
    val.to_s
  when /^[-a-zA-Z0-9~!@#%^&*()_+=;:.,<>\/?|\t "]+$/, Time
    "'#{val}'"
  when /^[-a-zA-Z0-9~!@#%^&*()_+=;:.,<>\/?|\t '$]+$/
    "\"#{val}\""
  else
    Shellwords.shellescape(val)
  end
end

def get_program_env(_program, env)
  program_env = {}
  args = []

  return program_env, args if env.nil?

  case env
  when String
    args = Shellwords.shellsplit(env).map { |s| shell_escape_expand(s) }
  when Integer, Float
    args = env.to_s
  when Hash
    env.each do |k, v|
      case v
      when Hash
        v.each do |kk, vv|
          program_env[kk] = vv
        end
      else
        program_env[k] = v
      end
    end
  end

  [program_env, args]
end

class Job2sh < Job
  def out_line(line = nil)
    if line.nil?
      return if @script_lines[-1].nil?
      return if @script_lines[-1] =~ /^[\s{]*$/
      return if @script_lines[-1] =~ /^\s*(then|do)$/
    end
    @script_lines << line
  end

  def exec_line(line = nil)
    out_line line if @cur_func == :run_job
  end

  def indent(ancestors)
    "\t" * (@cur_func == :extract_stats ? 1 : 1 + ancestors.size)
  end

  def shell_header
    out_line '#!/bin/sh'
    out_line
  end

  def shell_export_env(tabs, key, val)
    exec_line tabs + "export #{key}=" + shell_escape_expand(val)
  end

  def shell_run_program(tabs, program, env)
    program_env, args = get_program_env(program, env)
    program_path = @programs[program] || @monitors[program] || program

    args = [] if program_path.index('/stats/') || program_path =~ /programs\/.+\/parse$/

    case program_path
    when /programs\/.+\/run$/
      # fake the program_dir to be used by later program_dir comparison
      program_dir = File.join(File.dirname(program_path), 'tests')
      wrapper = File.join(lkp_src, 'tests', 'wrapper')
    when /programs\/.+\/parse$/
      program_dir = File.join(File.dirname(program_path), 'stats')
      wrapper = File.join(lkp_src, 'stats', 'wrapper')
    when /\/daemon$/
      program_dir = File.join(File.dirname(program_path), 'daemon')
      wrapper = File.join(lkp_src, 'daemon', 'wrapper')
    when /\/setup$/
      program_dir = File.join(File.dirname(program_path), 'setup')
      wrapper = File.join(lkp_src, 'setup', 'wrapper')
    else
      program_dir = File.dirname(program_path)
      wrapper = "#{program_dir}/wrapper"
    end

    cmd = if File.executable?(wrapper)
            [wrapper, program, *args]
          else
            [program_path, *args]
          end

    cmd.first.gsub!(LKP_SRC, '$LKP_SRC')
    cmd.first.gsub!(lkp_src, '$LKP_SRC')

    command = []
    case program_dir
    when %r{/monitors}
      command << 'run_monitor'
    when %r{/setup$}
      command << 'run_setup'
      # - 'fs2' will expand to empty in some job matrix;
      # - 'cpufreq_governor' will be defined in one include
      #    and redefined in another to be empty
      # They all mean to cancel running the setup script.
      return if program_env.empty? && args.empty? &&
                program =~ /^(fs2|cpufreq_governor)$/
    when %r{/daemon$}
      command << 'start_daemon'
    when %r{/tests$}
      command << 'run_test'
      @stats_lines << "\t$LKP_SRC/stats/wrapper time #{program}.time"
    else
      command << 'env' unless program_env.empty?
    end

    program_env.each do |k, v|
      command << "#{shell_encode_keyword(k)}=#{shell_escape_expand(v)}"
    end

    command.concat cmd

    exec_line unless command.first == 'run_monitor' && @script_lines[-1] =~ /run_monitor/
    out_line tabs + command.join(' ')
  end

  def parse_one(ancestors, key, val, pass)
    tabs = indent(ancestors)
    if @programs.include?(key) || (key =~ /^(call|command|source)\s/ && @cur_func == :run_job)
      if @setups.include?(key)
        return false unless pass == :PASS_RUN_SETUP
      else
        return false unless pass == :PASS_RUN_COMMANDS
      end
      shell_run_program(tabs, key.sub(/^call\s+/, '').sub(/^source\s+/, '.'), val)
      return :action_call_command
    elsif @monitors.include?(key)
      return false unless pass == :PASS_RUN_MONITORS

      shell_run_program(tabs, key, val)
      return :action_run_monitor
    elsif val.is_a?(String) && key =~ %r{^script\s+(monitors|setup|tests|daemon|stats)/([-a-zA-Z0-9_/]+)$}
      return false unless pass == :PASS_NEW_SCRIPT

      script_file = "#{$1}/#{$2}"
      script_name = File.basename $2
      if (@cur_func == :run_job && script_file =~ %r{^(setup|tests|daemon)/}) ||
         (@cur_func == :extract_stats && script_file.index('stats/')&.zero?)
        @programs[script_name] = "#{LKP_SRC}/#{script_file}"
      elsif @cur_func == :run_job && script_file =~ %r{^monitors/}
        @monitors[script_name] = "#{LKP_SRC}/#{script_file}"
      end
      exec_line
      exec_line tabs + "cat > $LKP_SRC/#{script_file} <<'EOF'"
      exec_line val
      exec_line 'EOF'
      exec_line tabs + "chmod +x $LKP_SRC/#{script_file}"
      exec_line
      return :action_new_script
    elsif val.is_a?(String) && key =~ /^(function)\s+([a-zA-Z_]+[a-zA-Z_0-9]*)$/
      return false unless pass == :PASS_NEW_SCRIPT

      shell_block = $1
      func_name = $2
      exec_line
      exec_line tabs + "#{func_name}()"
      exec_line tabs + SHELL_BLOCK_KEYWORDS[shell_block][0]
      val.each_line do |l|
        exec_line "\t#{tabs}#{l}"
      end
      exec_line tabs + SHELL_BLOCK_KEYWORDS[shell_block][1]
      return :action_new_function
    elsif val.is_a?(Hash) && key =~ /^(if|for|while|until)\s/
      return false unless pass == :PASS_RUN_COMMANDS

      shell_block = $1
      exec_line
      exec_line tabs + key.to_s
      exec_line tabs + SHELL_BLOCK_KEYWORDS[shell_block][0]
      parse_hash(ancestors + [key], val)
      exec_line tabs + SHELL_BLOCK_KEYWORDS[shell_block][1]
      return :action_control_block
    elsif val.is_a?(Hash)
      return false unless pass == :PASS_RUN_COMMANDS

      exec_line
      func_name = key.tr('^a-zA-Z0-9_', '_')
      exec_line tabs + "#{func_name}()"
      exec_line "#{tabs}{"
      parse_hash(ancestors + [key], val)
      exec_line "#{tabs}}\n"
      exec_line tabs + "#{func_name} &"
      return :action_background_function
    elsif valid_shell_variable?(key)
      return false unless pass == :PASS_EXPORT_ENV

      shell_export_env(tabs, key, val)
      return :action_export_env
    end
    nil
  end

  def parse_hash(ancestors, hash)
    nr_bg = 0
    hash.each { |key, val| parse_one(ancestors, key, val, :PASS_EXPORT_ENV) }
    hash.each { |key, val| parse_one(ancestors, key, val, :PASS_NEW_SCRIPT) } # rubocop:disable Style/CombinableLoops
    hash.each { |key, val| parse_one(ancestors, key, val, :PASS_RUN_SETUP) } # rubocop:disable Style/CombinableLoops
    # run monitors after setup:
    # monitors/iostat etc. depends on ENV variables by setup scripts
    hash.each { |key, val| parse_one(ancestors, key, val, :PASS_RUN_MONITORS) } # rubocop:disable Style/CombinableLoops
    hash.each { |key, val| nr_bg += 1 if parse_one(ancestors, key, val, :PASS_RUN_COMMANDS) == :action_background_function } # rubocop:disable Style/CombinableLoops

    # Disabled -- this will wait for the background monitors
    # started by run_monitor, while the monitors will wait for
    # wakup events signaled in post-run after run_job, which leads
    # to circular waits.
    # if nr_bg > 0
    #   exec_line
    #   exec_line indent(ancestors) + "wait"
    # end
  end

  def to_shell
    @script_lines = []
    @stats_lines = []

    shell_header

    @cur_func = :run_job

    out_line 'export_top_env()'
    out_line '{'
    @monitors = available_programs(:monitors)
    @setups   = available_programs(:setup)
    @programs = available_programs(:workload_elements)
    job = (@jobx || @job).clone # a shallow copy so that delete_if won't impact @job
    job.delete_if { |key, val| parse_one([], key, val, :PASS_EXPORT_ENV) }
    out_line
    out_line "\t[ -n \"$LKP_SRC\" ] ||"
    out_line "\texport LKP_SRC=/lkp/${user:-lkp}/src"
    out_line "}\n\n"

    out_line 'run_job()'
    out_line '{'
    out_line
    out_line "\techo $$ > $TMP/run-job.pid"
    out_line
    out_line "\t. $LKP_SRC/lib/http.sh"
    out_line "\t. $LKP_SRC/lib/job.sh"
    out_line "\t. $LKP_SRC/lib/env.sh"
    out_line
    out_line "\texport_top_env"
    out_line
    parse_hash [], job
    out_line "}\n\n"

    @cur_func = :extract_stats
    out_line 'extract_stats()'
    out_line '{'
    ajob = @jobx || @job
    out_line "\texport stats_part_begin=#{ajob['stats_part_begin']}"
    out_line "\texport stats_part_end=#{ajob['stats_part_end']}"
    out_line
    @monitors = {}
    @programs = available_programs(:stats)
    parse_hash [], job
    out_line
    out_line @stats_lines
    parse_hash [], YAML.load_file(LKP::Path.src('etc', 'default_stats.yaml'))
    out_line "}\n\n"

    out_line '"$@"'

    @script_lines
  end
end
