#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

MAX_MATRIX_COLS = 100
STATS_SOURCE_KEY = 'stats_source'.freeze

require 'set'
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/lkp_pattern"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/run_env"
require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/yaml"

LKP_SRC_ETC ||= LKP::Path.src('etc')

def event_counter?(name)
  LKP::EventCounterPrefixes.instance.contain?(name) || name =~ LKP::EventCounterPatterns.instance.regexp
end

def independent_counter?(name)
  LKP::IndependentCounterPrefixes.instance.contain?(name)
end

def ignore_part(name)
  LKP::IgnorePartPrefixes.instance.contain?(name)
end

def max_cols(matrix)
  cols = 0
  matrix.each_value do |v|
    cols = v.size if cols < v.size
  end
  cols
end

def matrix_fill_missing_zeros(matrix)
  cols = (matrix['stats_source'] || []).size
  matrix.each_value do |v|
    v << 0 while v.size < cols
  end
  matrix
end

def add_performance_per_watt(stats, matrix)
  watt = stats['pmeter.Average_Active_Power']
  return unless watt&.positive?

  kpi_stats = LKP::IndexPerfAll.instance.to_h
  return unless kpi_stats

  performance = 0
  kpi_stats.each do |stat, weight|
    next if 'boot-time.dhcp' =~ /^{stat}$/
    next if 'boot-time.boot' =~ /^{stat}$/
    # stat can be "iostat\..+\.wkB\/s"
    next if stat.index('iostat\.') && !stats['dd.startup_time']

    value = stats[stat]
    next unless value

    if weight.negative?
      value = 1 / value
      weight = -weight
    end
    performance += value * weight
  end

  return unless performance.positive?

  stats['pmeter.performance_per_watt'] = performance / watt
  matrix['pmeter.performance_per_watt'] = [performance / watt]
end

def add_path_length(stats, matrix)
  workloads = stats.select { |s| s.end_with? '.workload' }
  return if workloads.size != 1

  instructions = stats['perf-stat.total.instructions']
  return unless instructions

  path_length = instructions.to_f / workloads.values[0]
  stats['perf-stat.overall.path-length'] = path_length
  matrix['perf-stat.overall.path-length'] = [path_length]
end

def create_stats_matrix(result_root)
  stats = {}
  matrix = {}

  programs = Programs.create('programs/*/parse')

  monitor_files = Dir["#{result_root}/*.{json,json.gz}"]
  job = Job.open("#{result_root}/job.yaml")
  stats_part_begin = job['stats_part_begin'].to_f
  stats_part_end = job['stats_part_end'].to_f

  monitor_files.each do |file|
    next unless File.size?(file)

    case file
    when /\.json$/
      monitor = File.basename(file, '.json')
    when /\.json\.gz$/
      monitor = File.basename(file, '.json.gz')
    end

    next if monitor == 'stats' # stats.json already created?
    next if monitor == 'matrix'

    unless programs[monitor] || monitor =~ /^ftrace\.|.+\.time$/
      log_warn "skip unite #{file}: #{monitor} not in #{programs.keys}"
      next
    end

    monitor_stats = JSON.parse_cached file
    sample_size = max_cols(monitor_stats)

    i_stats_part_begin = 0
    stats_part_len = sample_size
    tv = monitor_stats["#{monitor}.time"]
    # ignore non-sequence and start/end results
    if tv && tv.size > 2
      tv0 = tv[0]
      # make it relative time
      tv = tv.map { |v| v - tv0 } if tv0 > 2 && (stats_part_begin != 0 || stats_part_end != 0)
      if stats_part_begin != 0
        i_stats_part_begin = tv.find_index { |v| v >= stats_part_begin } || sample_size
        stats_part_len -= i_stats_part_begin
      end
      if stats_part_end != 0
        i_end = tv.find_index { |v| v >= stats_part_end } || sample_size
        stats_part_len = i_end - i_stats_part_begin
      end
    end

    monitor_stats.each do |k, v|
      next if k == "#{monitor}.time"

      v = v[i_stats_part_begin, stats_part_len] unless ignore_part k
      next if !v || v.empty?

      stats[k] = if v.size == 1
                   v[0]
                 elsif independent_counter? k
                   v.sum
                 elsif event_counter? k
                   v[-1] - v[0]
                 else
                   v.sum(0.0) / stats_part_len
                 end
      stats["#{k}.max"] = v.max if add_max_latency?(k)
    end
    matrix.merge! monitor_stats
  end

  add_performance_per_watt(stats, matrix)
  add_path_length(stats, matrix)
  save_json(stats, "#{result_root}/stats.json")
  save_json(matrix, "#{result_root}/matrix.json", compress: true)
  if local_run?
    save_matrix_to_csv_file("#{result_root}/stats.csv", stats)
    save_matrix_to_csv_file("#{result_root}/matrix.csv", matrix)
  end
  stats
end

def load_create_stats_matrix(result_root)
  stats_file = "#{result_root}/stats.json"
  if File.exist? stats_file
    JSON.parse_cached stats_file
  else
    create_stats_matrix result_root
  end
end

def matrix_average(matrix)
  avg = {}
  matrix.each { |k, v| avg[k] = v.empty? ? 0 : v.average }
  avg
end

def matrix_stddev(matrix)
  stddev = {}
  matrix.each { |k, v| stddev[k] = v.empty? ? 0 : v.standard_deviation }
  stddev
end

def load_matrix_file(matrix_file)
  matrix = nil
  begin
    matrix = JSON.parse_cached(matrix_file) if File.exist? matrix_file
  rescue StandardError
    return
  end
  matrix
end

def shrink_matrix(matrix, max_cols)
  return unless matrix['stats_source']

  n = matrix['stats_source'].size - max_cols
  return unless n > 1

  empty_keys = []
  matrix.each do |k, v|
    v.shift n
    empty_keys << k if v.empty?
  end
  empty_keys.each { |k| matrix.delete k }
end

def matrix_delete_col(matrix, col)
  matrix.each_value do |v|
    v.delete_at col
  end
end

def unite_remove_denylist_stats(matrix)
  # sched_debug per-cpu stats usually change a lot among multiple running,
  # still keep statistic stats such as avg, min, max, stddev, etc.
  matrix.reject do |k, _v|
    k =~ /^sched_debug.*\.[0-9]+$/
  end
end

# When stats script is changed, some stats can be no longer existed.
# Remove these stats when rts are re-processed.
def unite_remove_empty_stats(matrix)
  matrix.reject { |_k, v| v.empty? || v.all? { |item| item.instance_of?(Integer) && item.zero? } }
end

def unite_to(stats, matrix_root, max_cols = nil, delete: false)
  matrix_file = "#{matrix_root}/matrix.json"

  matrix = load_matrix_file("#{matrix_root}/matrix.json")
  matrix ||= load_matrix_file("#{matrix_root}/matrix.yaml")

  if matrix && matrix[STATS_SOURCE_KEY]
    dup_col = matrix[STATS_SOURCE_KEY].index stats[STATS_SOURCE_KEY]
    matrix_delete_col(matrix, dup_col) if dup_col
  else
    matrix = {}
  end

  matrix = add_stats_to_matrix(stats, matrix) unless delete
  shrink_matrix(matrix, max_cols) if max_cols

  matrix = unite_remove_denylist_stats(matrix)
  matrix = unite_remove_empty_stats(matrix)

  save_json(matrix, matrix_file)
  matrix = matrix_fill_missing_zeros(matrix)
  save_matrix_to_csv_file("#{matrix_root}/matrix.csv", matrix) if local_run?
  matrix.delete 'stats_source'
  begin
    avg = matrix_average(matrix)
    stddev = matrix_stddev(matrix)
    save_json(avg, "#{matrix_root}/avg.json")
    save_json(stddev, "#{matrix_root}/stddev.json")
    if local_run?
      save_matrix_to_csv_file("#{matrix_root}/avg.csv", avg)
      save_matrix_to_csv_file("#{matrix_root}/stddev.csv", stddev)
    end
  rescue TypeError
    log_error "matrix contains non-number values, move to #{matrix_file}-bad"
    FileUtils.mv matrix_file, "#{matrix_file}-bad", force: true # never raises exception
  end
  matrix
end

# Undo unite_to's append for one rt: unite_to has no way to know in
# advance that a run will later be isolated as bad (e.g. the failure
# surfaces only after matrix.json was already saved), so a run whose
# unite ultimately fails still needs its column retracted here.
def remove_rt_from_matrix(result_root, matrix_root)
  matrix_file = "#{matrix_root}/matrix.json"

  matrix = load_matrix_file(matrix_file)
  return unless matrix && matrix[STATS_SOURCE_KEY]

  col = matrix[STATS_SOURCE_KEY].index "#{result_root}/stats.json"
  return unless col

  matrix_delete_col(matrix, col)
  matrix = unite_remove_empty_stats(matrix)

  save_json(matrix, matrix_file)
end

# serves as locate db
def save_paths(result_root, user)
  date_glob = Time.now.strftime('%F')
  FileUtils.mkdir_p File.join(KTEST_PATHS_DIR, date_glob)
  paths_file = "#{KTEST_PATHS_DIR}/#{date_glob}/#{date_glob}-#{user}"

  # to avoid confusing between .../1 and .../11, etc. when search/remove, etc.
  result_root += '/' unless result_root.end_with?('/')

  File.open(paths_file, 'a') do |f|
    f.puts(result_root)
  end
end

def merge_matrixes(matrixes)
  mresult = {}
  matrixes.each do |m|
    add_stats_to_matrix(m, mresult)
  end
  mresult
end

def check_warn_test_error(matrix, _result_root)
  ids = %w(
    last_state.is_incomplete_run
    last_state.exit_fail
    stderr.has_stderr
    pts.has_failure
  )

  ids.each do |errid|
    samples = matrix[errid]
    next unless samples
    next unless samples.last(10).sum == 10
    next if errid == 'last_state.is_incomplete_run' && matrix['dmesg.boot_failures']
    # $stderr.puts "The last 10 results all failed, check: #{errid} #{result_root}"
  end
end

def sort_matrix(matrix, key)
  key_index = matrix.keys.index key
  t = matrix.values.transpose
  t.sort_by! do |vs|
    vs[key_index]
  end
  values = t.transpose
  m = {}
  matrix.keys.each_with_index do |k, i|
    m[k] = values[i]
  end
  m
end

def save_matrix_as_csv(file, matrix, sep = ' ', fill = -1, _header: true)
  fill && cols = matrix.map { |_k, v| v.size }.max
  matrix.each do |k, vs|
    vs = Array vs
    fill && vs += [fill] * (cols - vs.size)
    fields = [k] + vs.map(&:to_s)
    file.puts fields.join(sep)
  end
end

def save_matrix_to_csv_file(file_name, matrix, sep = ',', header: true)
  File.open(file_name, 'w') do |f|
    save_matrix_as_csv(f, matrix, sep, nil, _header: header)
  end
end

def read_matrix_from_csv_file(file_name)
  matrix = {}
  return {} unless file_name
  return {} unless File.exist? file_name

  convert = lambda do |input|
    Integer(input, exception: false) || Float(input, exception: false) || input
  end

  File.readlines(file_name).each do |line|
    values = line.split
    key = values.shift
    matrix[key] = values.map { |v| convert[v] }
  end
  matrix
end

def print_matrix(matrix)
  ks = matrix.map { |k, _vs| k.size }.max
  matrix.each do |k, vs|
    printf "%-#{ks}s ", k
    vs.each do |v|
      s = format_number(v)
      printf '%-12s', s
    end
    puts
  end
end

def unite_params(result_root)
  unless File.directory? result_root
    log_error "#{result_root} is not a directory"
    return false
  end

  result_path = ResultPath.new
  result_path.parse_result_root result_root

  params_file = result_path.params_file
  params_root = File.dirname params_file

  if File.exist?(params_file) && Time.now - File.ctime(params_root) > 3600
    # no need to update params
    return true
  end

  params = {}
  params = YAML.load_file(params_file) if File.exist? params_file
  unless params.instance_of? Hash
    log_warn "failed to parse file #{params_file}"
    params = {}
  end

  job = Job.new
  begin
    job.load("#{result_root}/job.yaml")
  rescue StandardError
    return
  end

  job.each_param do |k, v, _option_type|
    if params[k]
      params[k] << v unless params[k].include? v
    else
      params[k] = [v]
    end
  end

  begin
    atomic_save_yaml_json params, params_file
  rescue StandardError => e
    log_error e
  end

  begin
    YAML.load_file(params_file)
  rescue StandardError => e
    log_warn "#{e.message}: failed to load #{params_file} after saving params from #{result_root}/job.yaml"
  end
end

def unite_stats(result_root, delete: false)
  unless File.directory? result_root
    log_error "#{result_root} is not a directory"
    return false
  end

  result_root = File.realpath result_root
  _result_root = File.dirname result_root
  __result_root = File.dirname _result_root

  stats = load_create_stats_matrix result_root

  return false if stats.nil?

  stats['stats_source'] = "#{result_root}/stats.json"

  unite_to(stats, _result_root, nil, delete: delete)
  begin
    __matrix = unite_to(stats, __result_root, 100, delete: delete)
    check_warn_test_error __matrix, result_root
  rescue StandardError => e
    log_warn e.formatted_headline
  end

  true
end
