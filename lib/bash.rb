LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'English'
require 'shellwords'
require 'tty-command'

# rli9 FIXME: find a way to combine w/ misc
module Bash
  class BashCallError < StandardError
    attr_reader :command, :stdout, :stderr, :exitstatus

    def initialize(command, stdout, stderr, exitstatus)
      @command = command
      @stdout = stdout
      @stderr = stderr
      @exitstatus = exitstatus

      super("Command failed with exit #{exitstatus}: #{command}: #{stderr}")
    end
  end

  class TimeoutError < StandardError
    attr_reader :command

    def initialize(command)
      @command = command
      super("Command timed out: #{command}")
    end
  end

  class << self
    # Usage:
    #   Bash.run("ls -l")                           # Runs in bash
    #   Bash.run("ls", "-l")                        # Runs directly (safer)
    #   Bash.run("grep x", returns: [0,1]) # Custom success codes
    #   Bash.run("slow", stream: true) { |line| ... } # Stream lines
    def run(*args, **options, &block)
      returns = options.delete(:returns) || [0]
      verbose = options.delete(:verbose)
      stream = options.delete(:stream)
      unsetenv_others = options.delete(:unsetenv_others)
      input = options.delete(:input)
      run_opts = input ? { input: input } : {}

      # Default block meant for streaming output if none provided (stream mode only)
      block ||= ->(line) { puts line } if stream

      cmd = if options.empty? && !verbose
              # Cache the TTY::Command instance for performance.
              # This is a class instance variable on the Bash module.
              (@default_cmd ||= TTY::Command.new(printer: :null, uuid: false))
            else
              TTY::Command.new(printer: verbose ? :pretty : :null, uuid: false, **options)
            end

      args = prepare_args(args, unsetenv_others)

      result = if stream
                 cmd.run!(*args, **run_opts) do |out, err|
                   # TTY::Command yields chunks, split them to match line-based expectation.
                   (out || err).each_line { |line| block.call(line.chomp) }
                 end
               else
                 cmd.run!(*args, **run_opts)
               end

      handle_result(result, args, returns, options, stream, block)
    rescue TTY::Command::TimeoutExceeded
      raise TimeoutError, args.join(' ')
    end

    def safe_grep(*args, **options, &)
      options[:returns] = [0, 1]
      run(*args, **options, &)
    end

    private

    def prepare_args(args, unsetenv_others)
      env = args.first.is_a?(Hash) ? args.shift : {}

      if unsetenv_others
        construct_env_i_args(args, env)
      else
        construct_bash_args(args, env)
      end
    end

    def construct_env_i_args(args, env)
      env_vars = env.map { |k, v| "#{k}=#{v}" }
      base = ['env', '-i'] + env_vars
      if args.size == 1
        base + ['bash', '-c', args.first]
      else
        base + args
      end
    end

    def construct_bash_args(args, env)
      args = ['bash', '-c', args.first] if args.size == 1
      args.unshift(env) unless env.empty?
      args
    end

    def handle_result(result, args, returns, options, stream, block)
      # Legacy Bash.run behavior (Post-run yield) if NOT streaming
      # Note: legacy behavior requires yielding (stdout, stderr, exit_status)
      if block && !stream
        block.call(result.out, result.err, result.exit_status)
      elsif !(options[:dry_run] || returns.include?(result.exit_status))
        # In dry_run mode, exit_status is 0, so this passes.
        raise BashCallError.new(args.join(' '), result.out, result.err, result.exit_status)
      end

      result.out.chomp
    end
  end
end
