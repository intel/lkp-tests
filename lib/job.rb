#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'English'
require 'fileutils'
require 'json'
require 'set'
require 'yaml'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/common"
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/erb"
require "#{LKP_SRC}/lib/hash"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/result"
require "#{LKP_SRC}/lib/run_env"

def restore(ah, copy)
  if ah.instance_of?(Hash)
    ah.clear.merge!(copy)
  elsif ah.instance_of?(Array)
    ah.clear.concat(copy)
  end
end

def expand_shell_var(env, o)
  s = o.to_s
  return s unless local_run?

  if s.index('$')
    s = Bash.run(env, "eval echo \"#{s}\"").chomp
  elsif s.index('/dev/disk/')
    files = {}
    s.split.each do |f|
      Dir.glob(f).each { |d| files[File.realpath d] = d }
    end
    s = files.keys.sort_by do |dev|
      dev =~ /(\d+)$/
      $1.to_i
    end.join ' '
  end
  s
end

def expand_toplevel_vars(env, hash)
  vars = {}
  hash.each do |key, val|
    next unless key.is_a?(String)

    case val
    when Hash
      vars[key] = expand_shell_var(env, val) if %w[disk boot_params].include? key
      next
    when nil
      vars[key] = nil
    when Array
      vars[key] = expand_shell_var(env, val[0]) if val.size == 1
    else
      vars[key] = expand_shell_var(env, val)
    end
  end
  vars
end

def string_or_hash_key(h)
  if h.instance_of?(Hash)
    # assert h.size == 1
    h.keys[0]
  else
    h
  end
end

def for_each_in(ah, set, pk = nil, &block)
  ah.each do |k, v|
    yield pk, ah, k, v if set.include?(k)
    next unless v.is_a?(Hash)

    for_each_in(v, set, k, &block)
  end
end

# programs[script] = full/path/to/script
def __create_programs_hash(glob, lkp_src)
  programs = {}
  Dir.glob("#{lkp_src}/#{glob}").each do |path|
    next if File.directory?(path)
    next if path =~ /\.yaml$/
    next if path =~ /\.[0-9]+$/

    unless File.executable?(path)
      log_warn "skip non-executable #{path}"
      next
    end

    file = glob =~ /^programs\// ? path.split('/')[-2] : File.basename(path)
    next if file == 'wrapper'

    if programs.include? file
      log_error "Conflict names #{programs[file]} and #{path}"
      next
    end
    programs[file] = path
  end
  programs
end

def create_programs_hash(glob, lkp_src = LKP_SRC)
  cache_key = [glob, lkp_src].join ':'
  $programs_cache ||= {}
  $programs =
    $programs_cache[cache_key] ||= __create_programs_hash(glob, lkp_src).freeze
end

def atomic_save_yaml_json(object, file)
  temp_file = file + "-#{tmpname}"
  File.open(temp_file, 'w') do |file|
    if temp_file.index('.json')
      lines = JSON.pretty_generate(object, allow_nan: true)
    else
      lines = YAML.dump(object)
      # create comment lines from symbols
      lines.gsub!(/^:#(.*):( |)$/, "\n#\\1")
      lines.gsub!(/^\? :#(.*)\n:( |)$/, "\n#\\1")
    end
    file.write(lines)
  end
  FileUtils.mv temp_file, file, force: true
end

def rootfs_filename(rootfs)
  rootfs.split(/[^a-zA-Z0-9._-]/)[-1]
end

def comment_to_symbol(str)
  :"#! #{str}"
end

def replace_symbol_keys(hash)
  return hash unless hash.is_a?(Hash)

  sh = {}
  hash.each do |k, v|
    sh[k.to_s] = v
  end
  sh
end

def read_param_map_rules(file)
  lines = File.read file
  rules = {}
  prev_rule = nil
  head = nil
  loop do
    head, rule, lines = lines.partition(/^\/(.*?[^\\])\/\s+/)
    head.chomp!
    rules[prev_rule] = head if prev_rule
    break if rule.empty?

    prev_rule = Regexp.new $1
  end
  rules[prev_rule] = head if prev_rule
  rules
end

class JobFileSyntaxError < RuntimeError
  def initialize(jobfile, syn_msg)
    @jobfile = jobfile
    super("Jobfile: #{jobfile}, syntax error: #{syn_msg}")
  end

  attr_reader :jobfile
end

class Job
  class ParamError < ArgumentError
  end

  class SyntaxError < ArgumentError
  end
end

class Job
  EXPAND_DIMS = %w(kconfig commit rootfs ltp_commit nvml_commit blktests_commit qemu_commit perf_test_commit linux_commit).freeze

  attr_reader :path_scheme, :referenced_programs
  attr_accessor :overrides, :defaults

  def initialize(job = {}, defaults = {}, overrides = {})
    @job = job
    @defaults = defaults # from auto includes
    @overrides = overrides # from command line
    @available_programs = {}
  end

  def source_file_symkey(file)
    comment_to_symbol file.sub("#{lkp_src}/", '')
  end

  def load(jobfile, expand_template: false)
    raise ArgumentError, "empty jobfile #{jobfile}" unless File.size?(jobfile)

    yaml = File.read jobfile
    # give a chance
    if yaml.empty?
      log_debug "start reload #{jobfile}"
      yaml = File.read jobfile
      if yaml.empty?
        log_debug "reload #{jobfile} failed"
      else
        log_debug "reload #{jobfile} succeed"
      end
    end

    raise ArgumentError, "nothing to load from #{jobfile}" if yaml.empty?

    # keep comment lines as symbols
    yaml.gsub!(/\n\n#([! ][-a-zA-Z0-9 !|\/?@<>.,_+=%~]+)$/, "\n:#\\1: ")

    begin
      yaml = expand_yaml_template(yaml, jobfile) if expand_template

      @jobs = []
      YAML.load_stream(yaml) do |hash|
        @jobs << hash
      end
    rescue StandardError => e
      log_error "#{jobfile}: " + e.message
      raise
    end

    @job = {}
    unless @jobs.first['job_origin']
      if File.symlink?(jobfile) &&
         File.readlink(jobfile) =~ %r|^../../../(.*)|
        @job[comment_to_symbol $1] = nil
      else
        @job[source_file_symkey jobfile] = nil
      end
    end
    @job.merge!(@jobs.shift)
    @job['job_origin'] ||= jobfile
    @jobfile = jobfile
  end

  def delete_keys_from_spec(spec_file)
    return unless File.exist? spec_file

    spec_file_context = load_yaml(spec_file, nil)
    spec_file_context.each_key { |k| @job.delete k }
  end

  def load_hosts_config
    return if @job.include?(:no_defaults)
    return unless @job.include? 'tbox_group'

    hosts_file = "#{lkp_src}/hosts/#{@job['tbox_group']}"
    return unless File.exist? hosts_file

    hwconfig = load_yaml(hosts_file, nil)
    @job[source_file_symkey(hosts_file)] = nil
    @job.merge!(hwconfig) { |_k, a, _b| a } # job's key/value has priority over hwconfig
  end

  def include_files
    return @include_files if @include_files

    @include_files = {}
    Dir["#{lkp_src}/include/*"].map do |d|
      key = File.basename d
      @include_files[key] = {}

      Dir["#{lkp_src}/include/#{key}",
          "#{lkp_src}/include/#{key}/*"].each do |f|
        next if File.directory? f

        @include_files[key][File.basename(f)] = f
      end
    end

    Dir["#{lkp_src}/programs/*/include"].map do |f|
      key = File.basename(File.dirname(f))
      @include_files[key] = {}
      @include_files[key][key] = f
    end

    @include_files
  end

  def load_one_defaults(file, job)
    return unless File.exist? file

    context_hash = deepcopy(@defaults)
    revise_hash(context_hash, job, overwrite_top_keys: true)
    revise_hash(context_hash, @overrides, overwrite_top_keys: true)
    begin
      defaults = load_yaml(file, context_hash)
    rescue KeyError
      return false
    end
    if defaults.is_a?(Hash) && !defaults.empty?
      @defaults[source_file_symkey(file)] = nil
      revise_hash(@defaults, defaults, overwrite_top_keys: true)
    end
    true
  end

  def load_defaults(first_time: true)
    if @job.include? :no_defaults
      merge_defaults first_time: first_time
      return
    end

    if first_time
      @file_loaded = {}
    else
      @file_loaded ||= {}
    end

    i = include_files
    job = deepcopy(@job)
    revise_hash(job, deepcopy(@job2), overwrite_top_keys: true)
    revise_hash(job, deepcopy(@overrides), overwrite_top_keys: true)
    job['___'] = nil
    expand_each_in(job, @dims_to_expand) do |h, k, v|
      h.delete(k) if v.is_a?(Array)
    end
    @jobx = job
    expand_params(run_scripts: false)
    @jobx = nil
    for_each_in(job, i.keys) do |_pk, _h, k, v|
      job['___'] = v

      load_one = lambda do |f|
        break unless i[k][f]
        break if @file_loaded.include?(k) &&
                 @file_loaded[k].include?(f)

        break unless load_one_defaults(i[k][f], job)

        @file_loaded[k]  ||= {}
        @file_loaded[k][f] = true
      end

      if @referenced_programs.include?(k) && i.include?(k)
        next unless load_one[k].nil?

        if v.is_a?(Hash)
          v.each do |kk, vv|
            next unless @referenced_programs[k].include? kk

            job['___'] = vv
            load_one[kk]
          end
        end
      end
      next unless v.is_a?(String)

      # For testbox vm-lkp-wsx01-4G,
      # try "vm", "vm-lkp", "vm-lkp-wsx01", "vm-lkp-wsx01-4G" in turn.
      c = v
      prefix = ''
      hit = nil
      loop do
        a, b, c = c.partition(/[:-]/)
        prefix += a
        hit = load_one[prefix]
        break if c.empty?

        prefix += b
      end

      load_one['OTHERS'] if hit.nil?
      load_one['ALL']
    end

    merge_defaults first_time: first_time
  end

  def merge_defaults(first_time: true)
    revise_hash(@job, @defaults, overwrite_top_keys: false)
    @defaults = {}

    return unless first_time

    revise_hash(@job, @job2, overwrite_top_keys: true)

    return if @overrides.empty?

    key = comment_to_symbol('user overrides')
    @job.delete key
    @job[key] = nil
    revise_hash(@job, @overrides, overwrite_top_keys: true)
  end

  def save(jobfile)
    @job.delete :no_defaults
    atomic_save_yaml_json @job, jobfile
  end

  def lkp_src
    if @job['user'].is_a?(String) && Dir.exist?("/lkp/#{@job['user']}/src")
      "/lkp/#{@job['user']}/src"
    else
      LKP_SRC
    end
  end

  def available_programs(type)
    @available_programs[type] ||=
      case type
      when Array
        p = {}
        type.each do |t|
          p.merge! available_programs(t)
        end
        p
      when :workload_and_monitors
        # This is all scripts that run in testbox.
        # The other stats/* and filters/* run in server.
        available_programs %i(workload_elements monitors)
      when :workload_elements
        # the options of these programs could impact test result
        available_programs %i(setup tests daemon)
      else
        programs = create_programs_hash("#{type}/**/*", lkp_src)

        programs = programs.merge create_programs_hash('programs/*/run', lkp_src) if type == :tests
        programs = programs.merge create_programs_hash('programs/*/parse', lkp_src) if type == :stats

        programs
      end
  end

  def read_single_program(key, file)
    options = `#{LKP_SRC}/bin/program-options #{file}`.split("\n")
    @referenced_programs[key] = {}

    options.each do |line|
      type, name = line.split
      @program_options[name] = type
      @referenced_programs[key][name] = nil
    end
  end

  def init_program_options
    @referenced_programs = {}
    @program_options = {
      'cluster' => '-'
    }
    programs = available_programs(:workload_elements)
    for_each_in(@job, programs) do |_pk, _h, k, _v|
      read_single_program(k, programs[k])
    end

    read_single_program('wrapper', "#{LKP_SRC}/tests/wrapper")
    read_single_program('dwrapper', "#{LKP_SRC}/daemon/wrapper")
  end

  def each_job_init
    init_program_options
    @dims_to_expand = Set.new EXPAND_DIMS
    @dims_to_expand.merge @referenced_programs.keys
    @dims_to_expand.merge @program_options.keys
  end

  def expand_each_in(ah, set, &block)
    ah.each do |k, v|
      yield ah, k, v if set.include?(k) || (v.is_a?(String) && v =~ /{{(.*)}}/m)
      next unless v.is_a?(Hash)

      expand_each_in(v, set, &block)
    end
  end

  def each_job(&block)
    expand_each_in(@job, @dims_to_expand) do |h, k, v|
      if v.is_a?(String) && v =~ /^(.*){{(.*)}}(.*)$/m
        head = $1.lstrip
        tail = $3.chomp.rstrip
        expr = expand_expression(@job, $2, k)
        return if expr.nil?

        h[k] = if head.empty? && tail.empty?
                 expr
               else
                 "#{head}#{expr}#{tail}"
               end
        each_job(&block)
        h[k] = v
        return
      elsif v.is_a?(Array)
        v.each do |vv|
          h[k] = vv
          each_job(&block)
        end
        h[k] = v
        return
      end
    end
    job = deepcopy self
    job.load_defaults first_time: false
    job.delete :no_defaults
    yield job
  end

  def each_jobs(&)
    each_job_init
    load_hosts_config
    job = deepcopy(@job)
    @job2 = {}
    load_defaults
    each_job_init
    each_job(&)
    @jobs.each do |hash|
      @job = deepcopy(job)
      @job2 = hash
      load_defaults
      each_job_init
      each_job(&)
    end
  end

  def each_param
    init_program_options

    # Some programs, especially setup/*, can accept params directly
    # via command line string, ie.
    #
    #   program: param
    #
    # instead of the normal
    #
    #   program:
    #     option1: v1
    #     option2: v2
    #
    # So need to iterate programs, too.
    set = @program_options.merge available_programs(:workload_elements)

    # We also allow program options to be set non-locally, ie.
    #
    #   option1: param1
    #   program:
    #     option2: param2
    #
    monitors = available_programs(:monitors)
    for_each_in(@job, set) do |pk, _h, k, v|
      next if v.is_a?(Hash)

      # skip monitor options which happen to have the same
      # name with referenced :workload_elements programs
      next if pk && monitors.include?(pk)

      yield k, v, @program_options[k]
    end
  end

  def each_program(type)
    for_each_in(@job, available_programs(type)) do |_pk, _h, k, v|
      yield k, v
    end
  end

  def each(&)
    @job.each(&)
  end

  def monitor_params
    m = []
    each_program(:monitors) do |k, _v|
      m << k
    end
    m
  end

  def path_params
    sorted_params = []
    each_param { |k, v, option_type| sorted_params << [k, v, option_type] }
    sorted_params = sorted_params.sort_by { |k, _v, _option_type| k }

    path = ''
    sorted_params.each do |k, v, option_type|
      if option_type == '='
        path += if v && v != ''
                  "#{k}=#{v[0..30]}"
                else
                  k.to_s
                end
        path += '-'
        next
      end
      next unless v

      path += v.to_s[0..30]
      path += '-'
    end

    path.empty? ? 'defaults' : path.chomp('-').tr('^-a-zA-Z0-9+=:.%', '_')
  end

  def param_files
    @param_files ||= begin
      maps = {}
      ruby_scripts = {}
      misc_scripts = {}
      Dir["#{lkp_src}/params/*",
          "#{lkp_src}/filters/*"].map do |f|
        name = File.basename f
        case name
        when /(.*)\.rb$/
          ruby_scripts[$1] = f
        else
          if File.executable? f
            misc_scripts[name] = f
          else
            maps[name] = f
          end
        end
      end
      [maps, ruby_scripts, misc_scripts]
    end
  end

  def map_param(hash, key, val, rule_file)
    return unless val.is_a?(String)

    ___ = val.dup # for reference by expressions
    output = nil
    rules = read_param_map_rules(rule_file)
    rules.each do |pattern, expression|
      val.sub!(pattern) do |_s|
        # puts s, pattern, expression
        job = JobEval.new @jobx
        o = job.instance_eval(expression)
        case output
        when nil
          output = o
        when Hash
          output.merge! o
        else
          log_error "confused while mapping param: #{___}"
          break 2
        end
        nil
      end
    end
    hash[key] = replace_symbol_keys(output) if output
  end

  def evaluate_param(_hash, _key, val, script)
    hash = @jobx.merge(___: val)
    expr = File.read script
    expand_expression(hash, expr, script)
  end

  def job_env(job)
    job_env = {}
    for_each_in(job, available_programs(:workload_elements)) do |_pk, _h, program, env|
      if env.is_a? Hash
        env.each do |key, val|
          key = "#{program}_#{key}".gsub(/[^a-zA-Z0-9_]/, '_')
          job_env[key] = val.to_s
        end
      else
        job_env[program] = env.to_s
      end
    end
    job_env
  end

  def top_env(job)
    top_env = expand_toplevel_vars({}, job)
    top_env['LKP_SRC'] = lkp_src
    top_env['job_file'] = job['job_file'] || @jobfile
    top_env
  end

  def run_filter(_hash, _key, _val, script)
    Bash.run(@filter_env, script, unsetenv_others: true) do |stdout, _stderr, status|
      unless status.zero?
        puts stdout
        raise Job::ParamError, "#{script}: exitstatus #{status}. Output: #{stdout}"
      end
    end
  end

  def expand_params(run_scripts: true)
    @jobx ||= deepcopy @job
    maps, ruby_scripts, misc_scripts = param_files
    begin
      hash = nil
      file = nil
      for_each_in(@jobx, maps.keys.to_set) do |_pk, h, k, v|
        hash = h
        file = maps[k]
        map_param(h, k, v, file)
      end
      return true unless run_scripts

      for_each_in(@jobx, ruby_scripts.keys.to_set) do |_pk, h, k, v|
        hash = h
        file = ruby_scripts[k]
        evaluate_param(h, k, v, file)
      end
      @filter_env = top_env(@jobx).merge(job_env(@jobx))
      for_each_in(top_env(@jobx), misc_scripts.keys.to_set) do |_pk, h, k, v|
        hash = h
        file = misc_scripts[k]
        run_filter(h, k, v, file)
      end
    rescue TypeError => e
      log_error "#{file}: #{e.message} hash: #{hash}"
      raise
    rescue KeyError => e # no conclusion due to lack of information
      log_error "#{file}: #{e.message} hash: #{hash}"
      return
    end
    true
  end

  def axes
    as = {}
    ResultPath::MAXIS_KEYS.each do |k|
      next if k == 'path_params'

      as[k] = @job[k] if @job.key? k
    end

    ## TODO: remove the following lines when we need not
    ## these default processing in the future
    rtp = ResultPath.new
    rtp['testcase'] = @job['testcase']
    path_scheme = rtp.path_scheme
    as['rootfs'] ||= 'debian-x86_64.cgz' if path_scheme.include? 'rootfs'
    as['compiler'] ||= LKP_DEFAULT_COMPILER if path_scheme.include? 'compiler'

    as['rootfs'] = rootfs_filename as['rootfs'] if as.key? 'rootfs'
    each_param do |k, v, option_type|
      as[k] = v.to_s if option_type == '=' || v
    end
    as
  end

  def each_commit
    return enum_for(__method__) unless block_given?

    @job.each do |key, val|
      case key
      when 'commit'
        yield val, @job['branch'], 'linux'
      when 'head_commit', 'base_commit'
        nil
      when /_commit$/
        project = key.sub(/_commit$/, '')
        yield val, @job["#{project}_branch"], project
      end
    end
  end

  # TODO: reimplement with axes
  def _result_root
    result_path = ResultPath.new
    result_path.update @job
    @path_scheme = result_path.path_scheme
    result_path['rootfs'] ||= 'debian-x86_64.cgz'
    result_path['rootfs'] = rootfs_filename result_path['rootfs']
    result_path['path_params'] = path_params
    result_path._result_root
  end

  def _boot_result_root(commit)
    result_path = ResultPath.new
    result_path.update @job
    result_path['testcase'] = 'boot'
    result_path['path_params'] = '*'
    result_path['rootfs'] = '*'
    result_path['commit'] = commit
    result_path._result_root
  end

  def [](k)
    @job[k]
  end

  def []=(k, v)
    @job[k] = v
  end

  def include?(k)
    @job.include?(k)
  end

  def key?(k)
    @job.include?(k)
  end

  def empty?
    @job.empty?
  end

  def delete(k)
    @job.delete(k)
  end

  def update(k)
    @job.update(k)
  end

  def merge(k)
    @job.merge(k)
  end

  def to_hash
    @job
  end

  def atomic_job?
    @job['arch']
  end
end

class JobEval < Job
  def method_missing(method, *args, &)
    job = @job
    method = method.to_s
    if method.chomp!('=')
      job[method] = args.first
    elsif job.include? method
      job[method]
    else
      raise KeyError, "unknown hash key: '#{method}'"
    end
  end
end

class << Job
  def open(jobfile, expand_template: false)
    j = new
    j.load(jobfile, expand_template: expand_template) && j
  end
end

def each_job_in_dir(dir, job_name = '*.yaml')
  return enum_for(__method__, dir, job_name) unless block_given?

  proc_jobfile = lambda do |jobfile|
    j = Job.open jobfile
    j['jobfile'] = jobfile
    yield j
  end

  Dir.glob(File.join(dir, '**', job_name)).each(&proc_jobfile)
end
