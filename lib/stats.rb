#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'set'
require 'timeout'
require "#{LKP_SRC}/lib/bounds"
require "#{LKP_SRC}/lib/changed_stat"
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/lkp_git"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/lkp_pattern"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/perf_metrics"
require "#{LKP_SRC}/lib/programs"
require "#{LKP_SRC}/lib/result"
require "#{LKP_SRC}/lib/statistics"
require "#{LKP_SRC}/lib/tests"
require "#{LKP_SRC}/lib/yaml"

MARGIN_SHIFT = 5
MAX_RATIO = 5

LKP_SRC_ETC ||= LKP::Path.src('etc')

$metric_add_max_latency = File.read("#{LKP_SRC_ETC}/add-max-latency").split("\n")
$metric_failure = File.read("#{LKP_SRC_ETC}/failure").split("\n")
$metric_pass = File.read("#{LKP_SRC_ETC}/pass").split("\n")
$perf_metrics_threshold = YAML.load_file "#{LKP_SRC_ETC}/perf-metrics-threshold.yaml"
$index_perf = load_yaml "#{LKP_SRC_ETC}/index-perf-all.yaml"
$index_latency = load_yaml "#{LKP_SRC_ETC}/index-latency-all.yaml"

class LinuxTestcasesTableSet
  def self.load_testcases(file_path)
    if File.exist?(file_path)
      File.readlines(file_path).map(&:strip).reject(&:empty?)
    else
      log_warn "File not found: #{file_path}"
    end
  end

  LINUX_PERF_TESTCASES = load_testcases("#{LKP_SRC}/etc/linux-perf-test-cases").freeze
  LINUX_TESTCASES = load_testcases("#{LKP_SRC}/etc/linux-test-cases").freeze
  OTHER_TESTCASES = load_testcases("#{LKP_SRC}/etc/other-test-cases").freeze
end

def functional_test?(testcase)
  LinuxTestcasesTableSet::LINUX_TESTCASES.index testcase
end

def other_test?(testcase)
  LinuxTestcasesTableSet::OTHER_TESTCASES.index testcase
end

$test_prefixes = test_prefixes

def perf_metric?(name)
  LKP::PerfMetrics.instance.contain? name
end

# Check whether it looks like a reasonable performance change,
# to avoid showing unreasonable ones to humans in compare/mplot output.
def reasonable_perf_change?(name, delta, max)
  $perf_metrics_threshold.each do |k, v|
    next unless name =~ %r{^#{k}$}
    return false if max < v
    return false if delta < v / 2 && v.instance_of?(Integer)

    return true
  end

  case name
  when /^iostat/
    return max > 1
  when /^pagetypeinfo/, /^buddyinfo/, /^slabinfo/
    return delta > 100
  when /^proc-vmstat/, /meminfo/
    return max > 1000
  when /^lock_stat/
    case name
    when 'waittime-total'
      return delta > 10_000
    when 'holdtime-total'
      return delta > 100_000
    when /time/
      return delta > 1_000
    else # rubocop:disable Lint/DuplicateBranch
      return delta > 10_000
    end
  when /^interrupts/, /^softirqs/
    return max > 10_000
  end
  true
end

# sort key for reporting all changed stats
def stat_relevance(record)
  stat = record['stat']
  relevance = if stat[0..9] == 'lock_stat.'
                5
              elsif $test_prefixes.include? stat.sub(/\..*/, '.')
                100
              elsif perf_metric?(stat)
                1
              else
                10
              end
  [relevance, [record['ratio'], 5].min]
end

def sort_stats(stat_records)
  stat_records.keys.sort_by do |stat|
    order1 = 0
    order2 = 0.0
    stat_records[stat].each do |record|
      key = stat_relevance(record)
      order1 = key[0]
      order2 += key[1]
    end
    order2 /= $stat_records[stat].size
    - order1 - order2
  end
end

def matrix_cols(hash_of_array)
  if hash_of_array.nil? || hash_of_array.empty?
    0
  elsif hash_of_array['stats_source']
    hash_of_array['stats_source'].size
  else
    [hash_of_array.values[0].size, hash_of_array.values[-1].size].max
  end
end

def load_release_matrix(matrix_file)
  load_json matrix_file
rescue StandardError => e
  log_error e
  nil
end

def vmlinuz_dir(kconfig, compiler, commit)
  "#{KERNEL_ROOT}/#{kconfig}/#{compiler}/#{commit}"
end

def load_base_matrix_for_notag_project(git, rp, axis)
  base_commit = git.first_sha
  log_debug "#{git.project} doesn't have tag, use its first commit #{base_commit} as base commit"

  rp[axis] = base_commit
  base_matrix_file = "#{rp._result_root}/matrix.json"
  unless File.exist? base_matrix_file
    log_warn "#{base_matrix_file} doesn't exist."
    return
  end
  load_release_matrix(base_matrix_file)
end

def load_base_matrix(matrix_path, head_matrix, options) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  matrix_path = File.realpath matrix_path
  matrix_path = File.dirname matrix_path if File.file? matrix_path
  log_debug "matrix_path is #{matrix_path}"

  rp = ResultPath.new
  rp.parse_result_root matrix_path

  puts rp if ENV['LKP_VERBOSE']
  project = options['bisect_project'] || 'linux'
  axis = options['bisect_axis'] || 'commit'

  commit = rp[axis]
  matrix = {}
  tags_merged = []

  begin
    $git ||= {}
    axis_branch_name =
      if axis == 'commit'
        options['branch']
      else
        options[axis.sub('commit', 'branch')]
      end
    remote = axis_branch_name.split('/')[0] if axis_branch_name

    log_debug "remote is #{remote}"
    $git[project] ||= Git.open(project: project, remote: remote)
    git = $git[project]
  rescue StandardError => e
    log_error e
    return
  end

  return load_base_matrix_for_notag_project(git, rp, axis) if git.tag_names.empty?

  begin
    return unless git.commit_exist? commit

    version = nil
    is_exact_match = false
    version, is_exact_match = git.gcommit(commit).last_release_tag
    log_debug "project: #{project}, version: #{version}, is_exact_match: #{is_exact_match}"
  rescue StandardError => e
    log_error e
    return
  end

  # FIXME: remove it later; or move it somewhere in future
  if project == 'linux' && !version
    kconfig = rp['kconfig']
    compiler = rp['compiler']
    context_file = "#{vmlinuz_dir(kconfig, compiler, commit)}/context.yaml"
    version = nil
    if File.exist? context_file
      context = YAML.load_file context_file
      version = context['rc_tag']
      is_exact_match = false
    end
    unless version
      log_error "Cannot get base RC commit for #{commit}"
      return
    end
  end

  order = git.release_tag_order(version)
  unless order
    # ERR unknown version v4.3 matrix
    # b/c git repo like GIT_ROOT_DIR/linux keeps changing, it is possible
    # that git object is cached in an older time, and v4.3 commit 6a13feb9c82803e2b815eca72fa7a9f5561d7861 appears later.
    # - git.gcommit(6a13feb9c82803e2b815eca72fa7a9f5561d7861).last_release_tag returns [v4.3, false]
    # - git.release_tag_order(v4.3) returns nil
    # refresh the cache to invalidate previous git object
    git = $git[project] = Git.open(project: project)
    version, is_exact_match = git.gcommit(commit).last_release_tag
    order = git.release_tag_order(version)

    # FIXME: rli9 after above change, below situation is not reasonable, keep it for debugging purpose now
    unless order
      log_error "unknown version #{version} matrix: #{matrix_path} options: #{options}"
      return
    end
  end

  cols = 0
  git.release_tags_with_order.each do |tag, o|
    break if tag == 'v4.16-rc7' # kbuild doesn't support to build kernel < v4.16
    next if o >  order
    next if o == order && is_exact_match
    next if is_exact_match && tag =~ /^#{version}-rc[0-9]+$/
    break if tag =~ /\.[0-9]+$/ && tags_merged.size >= 2 && cols >= 6

    rp[axis] = tag
    base_matrix_file = "#{rp._result_root}/matrix.json"
    unless File.exist? base_matrix_file
      rp[axis] = git.release_tags2shas[tag]
      next unless rp[axis]

      base_matrix_file = "#{rp._result_root}/matrix.json"
    end
    next unless File.exist? base_matrix_file

    log_debug "base_matrix_file: #{base_matrix_file}"
    rc_matrix = load_release_matrix base_matrix_file
    next unless rc_matrix

    add_stats_to_matrix(rc_matrix, matrix)
    tags_merged << tag

    options['base_matrixes'] ||= {}
    options['base_matrixes'][tag] = rc_matrix

    cols += (rc_matrix['stats_source'] || []).size
    break if tags_merged.size >= 3 && cols >= 9
    break if tag =~ /-rc1$/ && cols >= 3
  end

  if matrix.empty?
    log_debug "no release matrix was found: #{matrix_path}"
    nil
  elsif cols >= 3 ||
        (cols >= 1 && functional_test?(rp['testcase'])) ||
        head_matrix['last_state.is_incomplete_run'] ||
        head_matrix['dmesg.boot_failures'] ||
        head_matrix['stderr.has_stderr']
    log_debug "compare with release matrix: #{matrix_path} #{tags_merged}"
    options['good_commit'] = tags_merged.first
    matrix
  else
    log_debug "release matrix too small: #{matrix_path} #{tags_merged}"
    nil
  end
end

def __function_stat?(stats_field)
  return false if stats_field.index('.time.')
  return false if stats_field.index('.timestamp:')
  return false if stats_field.index('.bootstage:')
  return true if $metric_failure.any? { |pattern| stats_field =~ %r{^#{pattern}} }
  return true if $metric_pass.any? { |pattern| stats_field =~ %r{^#{pattern}} }

  false
end

def function_stat?(stats_field)
  $function_stats_cache ||= {}
  if $function_stats_cache.include? stats_field
    $function_stats_cache[stats_field]
  else
    $function_stats_cache[stats_field] = __function_stat?(stats_field)
  end
end

def __latency_stat?(stats_field)
  $index_latency.keys.any? { |i| stats_field =~ /^#{i}$/ }
  false
end

def latency_stat?(stats_field)
  $latency_stat_cache ||= {}
  if $latency_stat_cache.include? stats_field
    $latency_stat_cache[stats_field]
  else
    $latency_stat_cache[stats_field] = __latency_stat?(stats_field)
  end
end

def failure_stat?(stats_field)
  $metric_failure.any? { |pattern| stats_field =~ %r{^#{pattern}} }
end

def pass_stat?(stats_field)
  $metric_pass.any? { |pattern| stats_field =~ %r{^#{pattern}} }
end

def memory_change?(stats_field)
  stats_field =~ /^(boot-meminfo|boot-memory|proc-vmstat|numa-vmstat|meminfo|memmap|numa-meminfo)\./
end

def add_max_latency?(stats_field)
  $metric_add_max_latency.any? { |pattern| stats_field =~ %r{^#{pattern}$} }
end

def sort_remove_margin(array, max_margin = nil)
  return [] if array.to_a.empty?

  margin = array.size >> MARGIN_SHIFT
  margin = [margin, max_margin].min if max_margin

  array = array.sorted
  array[margin..-margin - 1] || []
end

# NOTE: array *must* be sorted
def min_mean_max(array)
  return [0, 0, 0] if array.to_a.empty?

  [array[0], array[array.size / 2], array[-1]]
end

# Filter out data generated by incomplete run
def filter_incomplete_run(hash)
  is_incomplete_runs = hash['last_state.is_incomplete_run']
  return unless is_incomplete_runs

  delete_index_list = []
  is_incomplete_runs.each_with_index do |val, index|
    delete_index_list << index if val == 1
  end
  delete_index_list.reverse!

  hash.each_value do |v|
    delete_index_list.each do |index|
      v.delete_at(index)
    end
  end

  hash.delete 'last_state.is_incomplete_run'
end

def bisectable_stat?(stat)
  return true if LKP::StatAllowlist.instance.contain?(stat)

  !LKP::StatDenylist.instance.contain?(stat)
end

def samples_remove_boot_fails(matrix, samples)
  perf_samples = []
  samples.each_with_index do |v, i|
    next if matrix['last_state.is_incomplete_run'] &&
            matrix['last_state.is_incomplete_run'][i] == 1

    perf_samples << v
  end
  perf_samples
end

class StatSummary
  attr_reader :sorted, :min, :mean, :max

  def initialize(array, max_margin = nil)
    @sorted = sort_remove_margin(array, max_margin)
    @min, @mean, @max = min_mean_max(@sorted)
  end

  def len
    @max - @min
  end

  def size
    @sorted.size
  end

  def empty?
    @sorted.empty?
  end
end

class StatCompare
  attr_reader :k, :a_k, :b, :options, :is_incomplete_run, :cols_a, :cols_b, :resize, :is_force_stat, :is_function_stat, :is_latency_stat

  def initialize(k, a, b, is_incomplete_run, options)
    @k = k
    @a_k = a[k]
    @b = b
    @options = options
    @is_incomplete_run = is_incomplete_run
    @cols_a = matrix_cols(a)
    @cols_b = matrix_cols(b)
    @resize = options['resize']

    @is_force_stat = options["force_#{k}"]
    @is_function_stat = function_stat?(k)
    @is_latency_stat = latency_stat?(k)
  end

  def process
    return if skip_stat?

    # newly added monitors don't have values to compare in the base matrix
    return unless b[k] ||
                  is_function_stat ||
                  (k =~ /^(lock_stat|perf-profile)\./ && monitored_by_b?($1))

    summary_a, summary_b = calculate_matrix_values
    return unless summary_a

    return if !is_force_stat && !changed_stats?(summary_a, summary_b)

    return if skip_critical_stat?(summary_a)

    max, x, y, z, delta, ratio = StatCompare.calc_stats_metrics(summary_a, summary_b)
    return if skip_small_change?(ratio, delta, max)

    { 'stat' => k,
      'interval' => StatCompare.format_interval(summary_a, summary_b),
      'a' => summary_a.sorted,
      'b' => summary_b.sorted,
      'ttl' => Time.now,
      'is_function_stat' => is_function_stat,
      'is_latency' => is_latency_stat,
      'ratio' => ratio,
      'delta' => delta,
      'mean_a' => summary_a.mean,
      'mean_b' => summary_b.mean,
      'x' => x,
      'y' => y,
      'z' => z,
      'min_a' => summary_a.min,
      'max_a' => summary_a.max,
      'min_b' => summary_b.min,
      'max_b' => summary_b.max,
      'max' => max,
      'nr_run' => a_k.size }
  end

  private

  def monitored_by_b?(key)
    @b_monitors ||= {}
    return @b_monitors[key] if @b_monitors.key?(key)

    @b_monitors[key] = b.keys.any? { |k| stat_key_base(k) == key }
  end

  def changed_function_stat?(a, b)
    a.max != b.max
  end

  def changed_latency_stat?(a, b)
    if options['distance']
      # auto start bisect only for big regression
      return false if b.size <= 3 && a.size <= 3
      return false if b.size <= 3 && a.min < 2 * options['distance'] * b.max
      return false if a.max < 2 * options['distance'] * b.max
      return false if a.mean < options['distance'] * b.max

      true
    elsif options['gap']
      gap?(a, b, options['gap'])
    else
      return true if a.max > 3 * b.max
      return true if b.max > 3 * a.max

      false
    end
  end

  def changed_perf_stat?(a, b)
    if options['variance']
      return true if a.len * b.mean > options['variance'] * b.len * a.mean
      return true if b.len * a.mean > options['variance'] * a.len * b.mean
    elsif options['gap']
      return true if gap?(a, b, options['gap'])
    else # options['distance']
      cs = LKP::ChangedStat.new k, a.sorted, b.sorted, options

      return true if cs.change?
    end

    false
  end

  def changed_stats?(a, b)
    if options['perf-profile'] && k =~ /^perf-profile\./ && options['perf-profile'].is_a?(a.mean.class)
      return a.mean > options['perf-profile'] ||
             b.mean > options['perf-profile']
    end

    return changed_function_stat?(a, b) if is_function_stat
    return changed_latency_stat?(a, b) if is_latency_stat

    changed_perf_stat?(a, b)
  end

  # Check if there is a significant separation between the value ranges of two datasets
  #
  # Condition for b > a (and vice versa for a > b):
  #
  #       [  Range A  ]                   [   Range B   ]
  #       |___________|                   |_____________|
  #      min         max                 min           max
  #                   <--- Gap Width --->
  #                   |                 |
  #      |           |                   |             |
  #    mean A        |                   |           mean B
  #                  |                   |
  #                  |<--- Mean Diff --->|
  #
  #    Gap Width > Mean Diff * gap_factor
  #
  def gap?(a, b, gap)
    return true if b.min > a.max && (b.min - a.max) > (b.mean - a.mean) * gap
    return true if a.min > b.max && (a.min - b.max) > (a.mean - b.mean) * gap

    false
  end

  def skip_critical_stat?(summary_a)
    return false unless (options['regression-only'] || options['all-critical']) && is_function_stat

    if summary_a.max.zero?
      options['has_boot_fix'] = true if k =~ /^dmesg\./
      return true if options['regression-only'] ||
                     (!LKP::DmesgKillPattern.instance.contain?(k) && options['all-critical'])
    end

    # this relies on the fact dmesg.* comes ahead
    # of kmsg.* in etc/default_stats.yaml
    return true if options['has_boot_fix'] && k =~ /^kmsg\./

    false
  end

  def skip_function_stat?
    return false if is_force_stat
    return false if k =~ /^(dmesg|kmsg|last_state|stderr)\./

    # if stat is packetdrill.packetdrill/gtests/net/tcp/mtu_probe/basic-v6_ipv6.fail,
    # base rt stats should contain 'packetdrill.packetdrill/gtests/net/tcp/mtu_probe/basic-v6_ipv6.pass'
    stat_base = k.sub(/\.[^.]*$/, '')
    # only consider pass and fail temporarily
    return true if k =~ /\.(error|warn|fail)$/ && !b.key?("#{stat_base}.pass")
    return true if k =~ /\.pass$/ && b.keys.none? { |stat| stat =~ /^#{stat_base}\.(error|warn|fail)$/ }

    false
  end

  def skip_regular_stat?
    # for none-failure stats field, we need asure that
    # at least one matrix has 3 samples.
    return true if !is_force_stat && cols_a < 3 && cols_b < 3 && !options['whole']

    # virtual hosts are dynamic and noisy
    return true if options['tbox_group'] =~ /^vh-/
    # VM boxes' memory stats are still good
    return true if options['tbox_group'] =~ /^vm-/ && !options['is_perf_test_vm'] && memory_change?(k)

    false
  end

  def skip_small_change?(ratio, delta, max)
    return false if is_force_stat
    return false if options['perf-profile'] && k =~ /^perf-profile\./

    return true unless ratio > 1.01 # time.elapsed_time only has 0.01s precision
    return true unless ratio > 1.05 || perf_metric?(k)
    return true unless reasonable_perf_change?(k, delta, max)

    false
  end

  def skip_stat?
    return true if a_k[-1].is_a?(String)
    return true if options['perf'] && !perf_metric?(k)
    return true if is_incomplete_run && k !~ /^(dmesg|last_state|stderr)\./
    return true if !options['more'] && !bisectable_stat?(k) && !LKP::ReportAllowlist.instance.contain?(k)

    if is_function_stat
      return true if skip_function_stat?
    elsif skip_regular_stat?
      return true
    end

    false
  end

  def calculate_matrix_values
    max_margin = if is_function_stat || is_latency_stat
                   0
                 else
                   3
                 end

    b_k = b[k] || ([0] * cols_b)
    b_k << 0 while b_k.size < cols_b
    a_k << 0 while a_k.size < cols_a

    summary_b = StatSummary.new(b_k, max_margin)
    return if summary_b.empty?

    a_k.pop(a_k.size - resize) if resize && a_k.size > resize

    max_margin = 1 if b_k.size <= 3 && max_margin > 1

    summary_a = StatSummary.new(a_k, max_margin)
    return if summary_a.empty?

    [summary_a, summary_b]
  end

  class << self
    def format_interval(a, b)
      interval_a = format('[ %-10.5g - %-10.5g ]', a.min, a.max)
      interval_b = format('[ %-10.5g - %-10.5g ]', b.min, b.max)

      "#{interval_a} -- #{interval_b}"
    end

    def calc_stats_metrics(a, b)
      max = [b.max, a.max].max
      x = a.len
      z = b.len
      x = z if a.size <= 2 && x < z

      if a.mean > b.mean
        y, delta, ratio = calc_diff_metrics(a, b)
      else
        y, delta, ratio = calc_diff_metrics(b, a)
      end

      y = 0 if y.negative?
      ratio = MAX_RATIO if ratio > MAX_RATIO
      [max, x, y, z, delta, ratio]
    end

    def calc_diff_metrics(high, low)
      y = high.min - low.max
      delta = high.mean - low.mean

      ratio = MAX_RATIO
      ratio = high.mean.to_f / low.mean if low.mean.positive?

      [y, delta, ratio]
    end
  end
end

# b is the base of compare (eg. rc kernels) and normally have more samples than
# a (eg. the branch HEADs)
def __get_changed_stats(a, b, is_incomplete_run, options)
  changed_stats = {}

  (b['last_state.booting'] && !a['last_state.booting'] if options['regression-only'] || options['all-critical'])

  cols_a = matrix_cols a
  cols_b = matrix_cols b

  return if options['variance'] && (cols_a < 10 || cols_b < 10)

  b.each_key { |k| a[k] = [0] * cols_a unless a.include?(k) }

  a.each_key do |k|
    comparator = StatCompare.new(k, a, b, is_incomplete_run, options)

    changed_stat = comparator.process
    next unless changed_stat

    changed_stats[k] = changed_stat.merge(options)
    next unless options['base_matrixes']

    changed_stats[k].delete('base_matrixes')
    changed_stats[k]['extra'] ||= {}
    changed_stats[k]['extra']['base_matrixes'] = options['base_matrixes'].map { |tag, matrix| "#{tag}: #{matrix[k].inspect}" }
  end

  changed_stats
end

def load_matrices_to_compare(matrix_path1, matrix_path2, options = {})
  a = search_load_json matrix_path1
  return [nil, nil] unless a

  b = if matrix_path2
        search_load_json matrix_path2
      else
        Timeout.timeout(1800) { load_base_matrix matrix_path1, a, options }
      end

  [a, b]
end

def find_changed_stats(matrix_path, options)
  changed_stats = {}

  rp = ResultPath.new
  rp.parse_result_root matrix_path

  rp.each_commit do |commit_project, commit_axis|
    next if commit_project == 'qemu'
    next if options['project'] && options['project'] != commit_project

    options['bisect_axis'] = commit_axis
    options['bisect_project'] = commit_project
    options['BAD_COMMIT'] = rp[commit_axis]

    puts options if ENV['LKP_VERBOSE']

    more_cs = get_changed_stats(matrix_path, nil, options)
    changed_stats.merge!(more_cs) if more_cs
  end

  changed_stats
end

def _get_changed_stats(a, b, options)
  is_incomplete_run = a['last_state.is_incomplete_run'] ||
                      b['last_state.is_incomplete_run']

  if is_incomplete_run && options['ignore-incomplete-run']
    changed_stats = {}
  else
    changed_stats = __get_changed_stats(a, b, is_incomplete_run, options)
    return changed_stats unless is_incomplete_run
  end

  # If reaches here, changed_stats only contains changed error ids.
  # Now remove incomplete runs to get any changed perf stats.
  filter_incomplete_run(a)
  filter_incomplete_run(b)

  is_all_incomplete_run = a['stats_source'].to_s.empty? ||
                          b['stats_source'].to_s.empty?
  return changed_stats if is_all_incomplete_run

  more_changed_stats = __get_changed_stats(a, b, false, options)
  changed_stats.merge!(more_changed_stats) if more_changed_stats

  changed_stats
end

def get_changed_stats(matrix_path1, matrix_path2 = nil, options = {})
  return find_changed_stats(matrix_path1, options) unless matrix_path2 || options['bisect_axis']

  puts <<-DEBUG if ENV['LKP_VERBOSE']
loading matrices to compare:
\t#{matrix_path1}
\t#{matrix_path2}
  DEBUG

  a, b = load_matrices_to_compare matrix_path1, matrix_path2, options
  return if a.nil? || b.nil?

  _get_changed_stats(a, b, options)
end

def add_stats_to_matrix(stats, matrix)
  return matrix unless stats

  columns = 0
  matrix.each_value { |v| columns = v.size if columns < v.size }
  stats.each do |k, v|
    matrix[k] ||= []
    matrix[k] << 0 while matrix[k].size < columns
    if v.is_a?(Array)
      matrix[k].concat v
    else
      matrix[k] << v
    end
  end
  matrix
end

def matrix_from_stats_files(stats_files, stats_field = nil, add_source: true)
  matrix = {}
  stats_files.each do |stats_file|
    stats = load_json stats_file
    unless stats
      log_warn "empty or non-exist stats file #{stats_file}"
      next
    end

    stats = stats.select { |k, _v| k == stats_field || k == 'stats_source' } if stats_field
    stats['stats_source'] ||= stats_file if add_source
    matrix = add_stats_to_matrix(stats, matrix)
  end
  matrix
end

def samples_fill_missing_zeros(matrix, key)
  size = matrix_cols matrix
  samples = matrix[key] || ([0] * size)
  samples << 0 while samples.size < size
  samples
end

def stat_key_base(stat)
  stat.partition('.').first
end

def strict_kpi_stat?(stat, _axes, _values = nil)
  $index_perf.keys.any? { |i| stat =~ /^#{i}$/ } || $index_latency.keys.any? { |i| stat =~ /^#{i}$/ }
end

$kpi_stat_denylist = Set.new ['vm-scalability.stddev', 'unixbench.incomplete_result']

def kpi_stat?(stat, _axes, _values = nil)
  return false if $kpi_stat_denylist.include?(stat)

  base, _, remainder = stat.partition('.')
  all_tests_set.include?(base) && !remainder.start_with?('time.')
end

def sort_bisect_stats(stats)
  monitor_stats = Dir["#{LKP_SRC}/monitors/*"].map { |m| File.basename m }
  stats.sort_by do |stat|
    stat_name = stat[Compare::STAT_KEY]
    score = monitor_stats.include?(stat_name.split('.').first) ? -100 : 0
    key = $index_perf.keys.find { |i| stat_name =~ /^#{i}$/ }
    $index_perf[key] ? $index_perf[key].to_i + score : -255 # -255 is a error value that should be less than values in $index_perf
  end
end

def kpi_stat_direction(stat_name, stat_change_percentage)
  key_direction = nil
  key = $index_perf.keys.find { |i| stat_name =~ /^#{i}$/ }
  if key
    key_direction = $index_perf[key]
  else
    key = $index_latency.keys.find { |i| stat_name =~ /^#{i}$/ }
    key_direction = $index_latency[key] if key
  end

  if key_direction.nil?
    'undefined'
  elsif (key_direction * stat_change_percentage).negative?
    'regression'
  else
    'improvement'
  end
end
