LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'optparse'
require 'set'
require "#{LKP_SRC}/lib/axis"
require "#{LKP_SRC}/lib/common"
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/enumerator"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/result_root"
require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/tests"

# How many components in the stat sort key
$stat_sort_key_number = {
  'perf-profile' => 2
}

$stat_absolute_changes = [
  /^perf-profile/,
  /%$/
]

class AxesGrouper
  include Property

  prop_with :group_axis_keys, :axes_data, :ignore_common_axes, :compare_runs

  private

  def calc_common_axes(axes)
    as = deepcopy(axes)
    group_axis_keys.each { |k| as.delete k }
    as
  end

  public

  def group
    map = {}
    if @compare_runs.to_a.many?
      @compare_runs.size.times do
        as = {}
        map[as] ||= AxesGroup.new self, as, 'compare_runs' => @compare_runs
        map[as].add_axes_datum @axes_data.first
      end
    else
      @axes_data.each do |d|
        as = @ignore_common_axes ? {} : calc_common_axes(d.axes)
        as.freeze
        map[as] ||= AxesGroup.new self, as
        map[as].add_axes_datum d
      end
    end
    map.values
  end

  def global_common_axes
    as = deepcopy(@axes_data.first.axes)
    @axes_data.drop(1).each do |ad|
      ad_as = ad.axes
      as.select! { |k, v| v && v == ad_as[k] }
    end
    as
  end
end

class AxesGroup
  prop_with :axes, :axes_data

  def initialize(grouper, common_axes, options = {})
    @grouper = grouper
    @axes = common_axes
    @axes_data = []
    @compare_runs = options['compare_runs'] || []
  end

  def add_axes_datum(datum)
    @axes_data << datum
  end

  def group_axeses
    if @compare_runs.empty?
      group_axis_keys = @grouper.group_axis_keys
      @axes_data.map do |d|
        d.axes.select { |k, _v| group_axis_keys.index k }
      end
    else
      @compare_runs.map { |r| { 'runs' => r.to_s } }
    end
  end
end

def commits_to_string(commits)
  commits.map(&:to_s)
end

module Compare
  ABS_WIDTH = 10
  REL_WIDTH = 10
  ERR_WIDTH = 6

  STAT_KEY = :stat_key
  FAILURE = :failure
  GROUP = :group
  VALUES = :values
  RUNS = :runs

  STAT_BASE = :stat_base
  AVGS = :avgs
  MIN = :min
  MAX = :max
  STDDEVS = :stddevs
  FAILS = :fails
  CHANGES = :changes
  ABS_CHANGES = :abs_changes

  RUNS_STAT_KEY = 'runs'.freeze
  COMPLETE_RUNS_STAT_KEY = 'runs.complete'.freeze
  RUNS_STAT_KEYS = [RUNS_STAT_KEY, COMPLETE_RUNS_STAT_KEY].freeze

  class Comparer
    include Property

    # following properties are parameters for compare
    prop_reader :stat_calc_funcs
    prop_with :mresult_roots, :compare_axis_keys, :compare_different_rts, :compare_runs,
              :sort_mresult_roots, :dedup_mresult_roots,
              :use_all_stat_keys, :use_stat_keys,
              :use_testcase_stat_keys, :include_stat_keys,
              :include_all_failure_stat_keys, :filter_stat_keys,
              :filter_testcase_stat_keys, :filter_kpi_stat_keys,
              :filter_kpi_stat_strict_keys,
              :exclude_stat_keys, :exclude_result_roots,
              :allowed_stat,
              :gap, :more_stats, :perf_profile_threshold,
              :group_by_stat, :show_empty_group, :compact_show,
              :sort_by_group

    private

    def initialize(params = nil)
      @compare_different_rts = false
      @compare_runs = []
      @show_empty_group = false
      @sort_mresult_roots = true
      @dedup_mresult_roots = true
      @gap = nil
      @allowed_stat = nil
      @exclude_result_roots = nil
      @perf_profile_threshold = 5
      apply_params params
      @stat_calc_funcs = [Compare.method(:calc_stat_change)]
    end

    # Convert string to hash:
    # "commit/1,2,3" => { commit => [1, 2, 3] }
    def convert_exclude_result_roots
      return if @exclude_result_roots.to_s.empty?

      arr = @exclude_result_roots.split('/')
      return { arr[0] => arr[1].split(',').delete_if(&:empty?) } if arr.size == 2 && sha1_40?(arr[0]) && arr[1] =~ /[0-9,]+/

      log_error "invalid exclude_result_roots #{@exclude_result_roots}, should be '<commit_sha_40>/<num_1>,<num_2>'"
      nil
    end

    public

    def apply_params(params)
      set_prop(*params.flatten) if params
      self
    end

    def do_sort_mresult_roots
      mrts = []
      @mresult_roots.each do |_rt|
        if !_rt.respond_to?(:path)
          # class MMResultRoot
          mrts << _rt
        elsif File.exist?(_rt.path) # rubocop:disable Lint/DuplicateBranch
          # class NMResultRoot
          mrts << _rt
        elsif ENV['LKP_VERBOSE']
          log_warn "#{_rt.path} not exist"
        end
      end
      return [] if mrts.empty?

      if sort_mresult_roots
        skeys = @compare_axis_keys.map do |k|
          git = axis_key_git(k)
          [k, git] if git
        end
        skeys.compact!
        unless skeys.empty?
          keys_values = skeys.map do |k, git|
            values = mrts.map { |_rt| _rt.axes[k] }
            values.compact!
            values.uniq!
            [k, commits_to_string(git.sort_commits(values))]
          end
          mrts.sort_by! do |_rt|
            axes = _rt.axes
            keys_values.map do |k, values|
              values.index(axes[k]) || -1
            end
          end
        end
      end
      mrts
    end

    def compare_groups
      mrts = do_sort_mresult_roots
      return [] if mrts.empty?

      mrts.uniq! if dedup_mresult_roots
      grouper = AxesGrouper.new
      groups = grouper.set_axes_data(mrts)
                      .set_compare_runs(@compare_runs)
                      .set_ignore_common_axes(@compare_different_rts)
                      .set_group_axis_keys(@compare_axis_keys)
                      .group
      groups.filter_map do |g|
        next if g.axes_data.size < 2

        Group.new self, g.axes, g.group_axeses, g.axes_data,
                  'compare_runs' => @compare_runs,
                  'allowed_stat' => @allowed_stat,
                  'exclude_result_roots' => convert_exclude_result_roots
      end
    end

    def global_common_axes
      grouper = AxesGrouper.new
      grouper.set_axes_data(@mresult_roots)
             .global_common_axes
    end

    # stat calc func is a function object with signature:
    # stat -> <ignored>
    def add_stat_calc_funcs(*calcs)
      @stat_calc_funcs += calcs
    end

    def each_changed_stat(&b)
      return enum_for(__method__) unless block_given?

      compare_groups.each do |g|
        g.each_changed_stat(&b)
      end
    end

    def do_compare
      compare_groups.map do |g|
        stat_enum = g.each_changed_stat
        begin
          stat_enum = Compare.sort_stats stat_enum
          GroupResult.new g, stat_enum
        rescue StandardError => e
          log_error e
          nil
        end
      end
    end

    def show_compare_result(compare_result)
      if group_by_stat
        Compare.show_by_stats compare_result
      else
        Compare.show_by_group compare_result
      end
    end

    # - select _result_roots: set_mresult_roots
    # - set compare axis: set_compare_axis
    # - get compare result: do_compare
    #   - group the result roots: compare_groups
    #   - calc changed stats keys: Group::calc_changed_stats
    #   - calc changes: in Group::each_changed_stat
    # - show compare result: show_compare_result
    def compare
      result = do_compare
      result = Compare.sort_group result if sort_by_group
      show_compare_result result
    end

    def to_data
      {
        compare_axis_keys: @compare_axis_keys,
        use_all_stat_keys: @use_all_stat_keys,
        use_stat_keys: @use_stat_keys,
        use_testcase_stat_keys: @use_testcase_stat_keys,
        include_stat_keys: @include_stat_keys,
        include_all_failure_stat_keys: @include_all_failure_stat_keys,
        filter_stat_keys: @filter_stat_keys,
        filter_testcase_stat_keys: @filter_testcase_stat_keys,
        filter_kpi_stat_keys: @filter_kpi_stat_keys,
        filter_kpi_stat_strict_keys: @filter_kpi_stat_strict_keys,
        group_by_stat: @group_by_stat,
        show_empty_group: @show_empty_group,
        compact_show: @compact_show,
        sort_by_group: @sort_by_group
      }
    end

    class << self
      def from_data(data)
        new data
      end
    end
  end

  class Group
    prop_reader :mresult_roots, :axes, :compare_axeses, :comparer

    private

    def initialize(comparer, axes, compare_axeses, mresult_roots, options = {})
      @comparer = comparer
      @axes = axes
      @mresult_roots = mresult_roots
      @compare_axeses = compare_axeses
      @compare_runs = options['compare_runs'] || []
      @allowed_stat = options['allowed_stat'] || ''
      @exclude_result_roots = options['exclude_result_roots'] || {}
    end

    public

    def each_run_matrixes(run)
      file = File.join(mresult_roots.first.mresult_root_path, run.to_s, 'matrix.json')
      content = if File.exist?(file)
                  File.read(file)
                elsif File.exist?("#{file}.gz")
                  Zlib::GzipReader.open("#{file}.gz").read
                else
                  ''
                end
      YAML.load(content)
    rescue StandardError
      {}
    end

    def update_matrix(mresult_root)
      matrix = mresult_root.matrix
      commit = File.basename(mresult_root.mresult_root_path)
      return matrix unless @exclude_result_roots[commit]

      @exclude_result_roots[commit].each do |i|
        stats_path = File.join(mresult_root.mresult_root_path, i, 'stats.json')
        stats = try_load_json(stats_path)
        next unless stats

        stats.each do |k, v|
          mv = matrix[k]
          matrix[k].delete_at(mv.index(v)) if mv.is_a?(Array) && mv.index(v)
        end
        matrix['stats_source'].delete_at(matrix['stats_source'].index(stats_path))
      end
      matrix
    end

    def matrixes
      if @exclude_result_roots.empty?
        mresult_roots.map { |_rt| _rt.matrix.freeze }
      else
        mresult_roots.map { |_rt| update_matrix(_rt).freeze }
      end
    end

    def complete_matrixes(ms = nil)
      ms ||= matrixes
      mresult_roots.zip(ms).map do |_rt, m|
        _rt.complete_matrix m
      end
    end

    def runs(ms = nil)
      ms ||= matrixes
      ms.map { |m| matrix_cols m }
    end

    def complete_runs(cms = nil)
      cms ||= complete_matrixes
      cms.map { |m| matrix_cols m }
    end

    def all_stat_keys
      stat_keys = []
      matrixes.each do |m|
        stat_keys |= m.keys
      end
      stat_keys.delete 'stats_source'
      stat_keys
    end

    def _calc_changed_stat_keys(matrixes_in)
      matrixes_in ||= matrixes
      changed_stat_keys = []
      ms = deepcopy(matrixes_in)
      m0 = ms[0]

      options = {
        'gap' => @comparer.gap,
        'more' => @comparer.more_stats,
        'perf-profile' => @comparer.perf_profile_threshold
      }
      options["force_#{@allowed_stat}"] = true unless @allowed_stat.empty?

      ms.drop(1).each do |m|
        changes = _get_changed_stats(m, m0, options)
        changed_stat_keys |= changes.keys if changes
      end
      changed_stat_keys
    end

    def do_filter_stat_keys(stats, filters)
      filters.map do |sre|
        re = Regexp.new(sre)
        stats.select { |stat_key| re.match stat_key }
      end.flatten
    end

    def include_stat_keys
      stat_key_res = @comparer.include_stat_keys
      return [] unless stat_key_res

      do_filter_stat_keys all_stat_keys, stat_key_res
    end

    def filter_stat_keys(stats)
      filters = @comparer.filter_stat_keys
      return stats unless filters && !filter.empty?

      do_filter_stat_keys stats, filters
    end

    def exclude_stat_keys(stats)
      excludes = @comparer.exclude_stat_keys
      return stats unless excludes && !excludes.empty?

      excludes.each do |sre|
        re = Regexp.new(sre)
        stats.reject! { |stat_key| re.match stat_key }
      end
      stats
    end

    def include_all_failure_stat_keys
      return [] unless @comparer.include_all_failure_stat_keys

      all_stat_keys.select { |stat_key| function_stat?(stat_key) }
    end

    def do_filter_testcase_stat_keys(stats)
      stats.select do |k|
        base, _, remainder = k.partition('.')
        all_tests_set.include?(base) && !remainder.start_with?('time.')
      end
    end

    def testcase_stat_keys
      do_filter_testcase_stat_keys all_stat_keys
    end

    def filter_testcase_stat_keys(stats)
      do_filter_testcase_stat_keys stats
    end

    def filter_kpi_stat_keys(stats, matrixes_in)
      stats.select do |k|
        kpi_stat?(k, axes, matrixes_in.map { |m| m[k] })
      end
    end

    def filter_kpi_stat_strict_keys(stats, matrixes_in)
      stats.select do |k|
        strict_kpi_stat?(k, axes, matrixes_in.map { |m| m[k] })
      end
    end

    def calc_changed_stat_keys(matrixes_in)
      stat_keys = if @comparer.use_all_stat_keys
                    all_stat_keys
                  elsif @comparer.use_stat_keys
                    @comparer.use_stat_keys
                  elsif @comparer.use_testcase_stat_keys
                    testcase_stat_keys
                  else
                    _calc_changed_stat_keys(matrixes_in)
                  end
      stat_keys |= include_stat_keys
      stat_keys |= include_all_failure_stat_keys
      stat_keys = filter_stat_keys stat_keys
      stat_keys = filter_testcase_stat_keys stat_keys if @comparer.filter_testcase_stat_keys
      stat_keys = filter_kpi_stat_keys stat_keys, matrixes_in if @comparer.filter_kpi_stat_keys
      stat_keys = filter_kpi_stat_strict_keys stat_keys, matrixes_in if @comparer.filter_kpi_stat_strict_keys
      exclude_stat_keys stat_keys
    end

    def changed_stat_keys(matrixes_in = nil)
      @changed_stat_keys ||= calc_changed_stat_keys(matrixes_in)
    end

    def each_changed_stat
      return enum_for(__method__) unless block_given?

      calc_funcs = @comparer.stat_calc_funcs

      if @compare_runs.empty?
        ms = matrixes
        cms = complete_matrixes ms
        aruns = runs ms
        cruns = complete_runs cms
      else
        ms = @compare_runs.map { |run| each_run_matrixes(run) }
        cms = ms
        aruns = 1
        cruns = 1
      end
      changed_stat_keys(ms).each do |stat_key|
        failure = function_stat?(stat_key)
        tms = failure ? ms : cms
        truns = failure ? aruns : cruns
        stat = {
          STAT_KEY => stat_key,
          FAILURE => failure,
          GROUP => self,
          VALUES => tms.map { |m| m[stat_key] },
          RUNS => truns
        }
        calc_funcs.each do |calc_func|
          calc_func.call(stat)
        end
        yield stat
      end
    rescue StandardError
      log_warn "Error while comparing: #{mresult_roots.map(&:to_s).join ' '}"
      raise
    end

    def to_data
      {
        comparer: @comparer.to_data,
        axes: @axes,
        mresult_roots: @mresult_roots.map(&:to_data),
        compare_axeses: @compare_axeses
      }
    end

    class << self
      def from_data(data)
        comparer = Comparer.from_data data[:comparer]
        _rts = data[:mresult_roots].map do |_rtd|
          NMResultRoot.from_data _rtd
        end
        comparer.set_mresult_roots _rts
        new comparer, data[:axes], data[:compare_axeses], _rts
      end
    end
  end

  class GroupResult
    def initialize(group, stat_enum)
      @group = group
      @stat_enum = stat_enum
    end

    prop_reader :group, :stat_enum

    def axes
      @group.axes
    end

    def axes_string(sep1 = '-', sep2 = '=')
      common_axes.map do |k, v|
        "#{k}#{sep2}#{v}"
      end.join sep1
    end

    def axes_value_string(sep = '-')
      common_axes.values.join sep
    end

    def compare_axeses
      @group.compare_axeses
    end

    def matrix_exporter
      MatrixExporter.new self
    end

    def score
      stat_enum.map do |s|
        s[CHANGES].map(&:abs).max || 0
      end.max || 0
    end

    def stats
      stat_enum.map do |s|
        s[STAT_KEY]
      end
    end

    def show
      Compare.show_group @group, @stat_enum
    end

    def to_data
      {
        group: @group.to_data,
        stats: Compare.stats_to_data(@stat_enum.to_a)
      }
    end

    class << self
      def from_data(data)
        group = Group.from_data(data[:group])
        stats = Compare.stats_from_data(data[:stats], group)
        GroupResult.new group, stats.each
      end
    end
  end

  class GroupResult
    class MatrixExporter
      include Property

      prop_with :data_types, :data_type, :include_axes, :axes_as_num,
                :axis_prefix, :sort, :sort_stat_key,
                :include_runs, :data_type_in_key, :group_result
      def initialize(group_result = nil)
        @group_result = group_result
        @data_types = [AVGS]
        @axes_as_num = true
        @axis_prefix = ''
        @sort = true
        @data_type_in_key = false
      end

      def data_type
        @data_types.first
      end

      def apply_data_type(dt)
        @data_types[0] = dt
        self
      end

      def matrix
        m = {}
        @group_result.stat_enum.each do |stat|
          stat_key = stat[STAT_KEY]
          if @data_types.size == 1 && !@data_type_in_key
            m[stat_key] = stat[@data_types.first]
          else
            @data_types.each do |dt|
              key = GroupResult::MatrixExporter.key_with_data_type(stat_key, dt)
              m[key] = stat[dt]
            end
          end
        end
        if @include_runs
          g = @group_result.group
          m[RUNS_STAT_KEY] = g.runs
          m[COMPLETE_RUNS_STAT_KEY] = g.complete_runs
        end
        m
      end

      def matrix_with_axes
        cas = @group_result.compare_axeses
        cas = cas.map { |as| Compare.axes_format as }
        cas_keys = cas[0].keys
        if @sort
          sort_key = @sort_stat_key ||
                     (@axis_prefix + cas_keys[0])
        end
        axis_converter = lambda { |axis_key|
          if @axes_as_num && (@axes_as_num == true ||
                  @axes_as_num.index(axis_key))
            method(:string_to_num)
          else
            ->(x) { x }
          end
        }

        m = {}
        cas_keys.each do |axis_key|
          conv = axis_converter.call(axis_key)
          m[@axis_prefix + axis_key] = cas.map do |as|
            conv.call(as[axis_key])
          end
        end
        m.merge!(matrix)
        m = sort_matrix(m, sort_key) if @sort
        m
      end

      def call
        if @include_axes
          matrix_with_axes
        else
          matrix
        end
      end

      class << self
        def key_with_data_type(key, data_type)
          "#{key}.#{data_type}"
        end
      end
    end
  end

  ## Stat load/store functions

  def self.stats_to_data(stats)
    stats.map do |stat|
      ns = stat.clone
      ns.delete GROUP
      ns
    end
  end

  def self.stats_from_data(stats, group)
    stats.each { |stat| stat[GROUP] = group }
  end

  ## Stat Calculation Functions

  def self.calc_failure_fail(stat)
    return unless stat[FAILURE]

    stat[FAILS] = stat[VALUES].map do |v|
      v ? v.sum : 0
    end
  end

  def self.calc_failure_change(stat)
    return unless stat[FAILURE]

    fs = stat[FAILS]
    runs = stat[RUNS]
    reproduce0 = fs[0].to_f / runs[0]
    stat[CHANGES] = fs.drop(1).each_with_index.map do |f, i|
      100 * ((f.to_f / runs[i]) - reproduce0)
    end
  end

  def self.calc_avg_stddev(stat)
    return if stat[FAILURE]

    vs = stat[VALUES]
    stat[AVGS] = vs.map { |v| v && !v.empty? ? v.average : 0 }
    stat[STDDEVS] = vs.map { |v| v && v.many? ? v.standard_deviation : -1 }
  end

  def self.calc_min_max(stat)
    return if stat[FAILURE]

    vs = stat[VALUES]
    stat[MIN] = vs.map { |v| v && !v.empty? ? v.min : 0 }
    stat[MAX] = vs.map { |v| v && !v.empty? ? v.max : 0 }
  end

  def self.use_absolute_changes?(key)
    $stat_absolute_changes.any? { |p| key =~ p }
  end

  def self.calc_perf_change(stat)
    return if stat[FAILURE]

    key = stat[STAT_KEY]
    avgs = stat[AVGS]
    avg0 = avgs[0]
    if use_absolute_changes? key
      stat[CHANGES] = avgs.drop(1).map do |avg|
        avg - avg0
      end
      stat[ABS_CHANGES] = true
    else
      # To avoid divide 0 problem
      avg0 = 1e-100 if avg0.zero?
      stat[CHANGES] = avgs.drop(1).map do |avg|
        100.0 * (avg - avg0) / avg0
      end
    end
  end

  def self.calc_stat_change(stat)
    calc_failure_fail stat
    calc_failure_change stat
    calc_avg_stddev stat
    calc_min_max stat
    calc_perf_change stat
  end

  ## Compare result renderer

  def self.sort_group(compare_result)
    compare_result.sort_by! { |gd| -gd.score }
  end

  def self.stat_sort_key(key, base)
    number = $stat_sort_key_number[base]
    if number
      key.split('.')[0, number].join '.'
    else
      key
    end
  end

  def self.sort_stats(stat_enum)
    stats = stat_enum.to_a
    stat_base_map = {}
    stats.each do |stat|
      base = stat_key_base stat[STAT_KEY]
      stat[STAT_BASE] = base
      stat_base_map[base] ||= stat[FAILURE] ? -10_000 : 0
      stat_base_map[base] += 1
    end
    all_tests_set.each do |test|
      c = stat_base_map[test]
      stat_base_map[test] = 0 if c&.positive?
    end
    stats.sort_by! do |stat|
      [
        stat_base_map[stat[STAT_BASE]],
        stat_sort_key(stat[STAT_KEY], stat[STAT_BASE]),
        stat[CHANGES]
      ]
    end
    stats.each
  end

  def self.show_failure_change(stat)
    return unless stat[FAILURE]

    fails = stat[FAILS]
    changes = stat[CHANGES]
    abs_changes = stat[ABS_CHANGES]
    runs = stat[RUNS]
    fails.each_with_index do |f, i|
      unless i.zero?
        if abs_changes
          printf "%#{REL_WIDTH}.0f  ", changes[i - 1]
        else
          printf "%#{REL_WIDTH}.0f%% ", changes[i - 1]
        end
      end
      if f.zero?
        printf "%#{ABS_WIDTH + 1}s", ' '
      else
        printf "%#{ABS_WIDTH + 1}d", f
      end
      printf ":%-#{ERR_WIDTH - 2}d", runs[i]
    end
  end

  def self.show_perf_change(stat)
    return if stat[FAILURE]

    avgs = stat[AVGS]
    stddevs = stat[STDDEVS]
    changes = stat[CHANGES]
    abs_changes = stat[ABS_CHANGES]
    avgs.each_with_index do |avg, i|
      unless i.zero?
        p = changes[i - 1]
        fmt = p.abs < 100_000 ? '.1f' : '.2g'
        if abs_changes
          printf "%+#{REL_WIDTH}#{fmt}  ", p
        else
          printf "%+#{REL_WIDTH}#{fmt}%% ", p
        end
      end
      fmt = if avg.abs < 1000
              '.2f'
            elsif avg.abs > 100_000_000
              '.4g'
            else
              'd'
            end
      printf "%#{ABS_WIDTH}#{fmt}", avg
      stddev = stddevs[i]
      stddev = 100 * stddev / avg if avg != 0
      if stddev > 2
        printf " ±%#{ERR_WIDTH - 3}d%%", stddev
      else
        printf ' ' * ERR_WIDTH
      end
    end
  end

  def self.show_stat(stat)
    printf "  %s\n", stat[STAT_KEY]
  end

  def self.axes_format(axes)
    naxes = {}
    axes.each do |k, v|
      nk, nv = axis_format k, v
      naxes[nk] = nv
    end
    naxes
  end

  def self.show_group_header(group)
    common_axes = axes_format group.axes
    compare_axeses = group.compare_axeses.map do |axes|
      axes_format axes
    end
    puts '========================================================================================='
    if common_axes.empty?
      group.mresult_roots.each do |rt|
        printf "%s:\n", rt.axes.keys.join('/')
        printf "  %s\n\n", rt.axes.values.join('/')
      end
    else
      printf "%s:\n", common_axes.keys.join('/')
      printf "  %s\n\n", common_axes.values.join('/')
    end
    printf "%s: \n", compare_axeses[0].keys.join('/')
    compare_axeses.each do |compare_axes|
      printf "  %s\n", compare_axes.values.join('/')
    end
    puts
    first_width = ABS_WIDTH + ERR_WIDTH
    width = first_width + REL_WIDTH + 1
    printf "%#{first_width}s ", compare_axeses[0].values.join('/')[0...first_width]
    compare_axeses.drop(1).each do |compare_axes|
      printf "%#{width}s ", compare_axes.values.join('/')[0...width]
    end
    puts
    printf "#{'-' * first_width} "
    compare_axeses.drop(1).size.times do
      printf "#{'-' * width} "
    end
    puts
  end

  def self.compact_show_group_header(group)
    common_axes = group.axes
    puts common_axes.map { |k, v| "#{k}=#{v}" }.join('/')
  end

  def self.show_perf_header(n = 1)
    # (ABS_WIDTH + ERR_WIDTH)   (2 + REL_WIDTH + ABS_WIDTH + ERR_WIDTH)
    #      |<-------------->|   |<--------------------------->|
    printf "         %%stddev#{'     %%change         %%stddev' * n}\n"
    printf "             \\  #{'        |                \  ' * n}\n"
  end

  def self.show_failure_header(n = 1)
    printf "       fail:runs#{'  %%reproduction    fail:runs' * n}\n"
    printf "           |    #{'         |             |    ' * n}\n"
  end

  def self.show_group(group, stat_enum)
    compact_show = group.comparer.compact_show

    failure, perf = stat_enum.partition { |stat| stat[FAILURE] }

    return if failure.empty? && perf.empty? && !group.comparer.show_empty_group

    if compact_show
      compact_show_group_header group
    else
      show_group_header group
    end
    nr_header = group.mresult_roots.size - 1

    unless failure.empty?
      show_failure_header(nr_header) unless compact_show
      failure.each do |stat|
        show_failure_change stat
        show_stat stat
      end
    end

    unless perf.empty?
      show_perf_header(nr_header) unless compact_show
      perf.each do |stat|
        show_perf_change stat
        show_stat stat
      end
    end

    puts
  end

  def self.show_by_group(compare_result)
    compare_result.each do |gd|
      show_group gd.group, gd.stat_enum
    end
  end

  def self.group_by_stat(stat_enum)
    stat_map = {}
    stat_enum.each do |stat|
      key = stat[STAT_KEY]
      stat_map[key] ||= []
      stat_map[key] << stat
    end
    stat_map
  end

  def self.show_by_stats(compare_result)
    stat_enums = compare_result.map do |d|
      sort_stats d.stat_enum
    end
    stat_enum = EnumeratorCollection.new(*stat_enums)
    stat_map = group_by_stat(stat_enum)
    stat_map.each do |stat_key, stats|
      puts "#{stat_key}:"
      stats.each do |stat|
        if stat[FAILURE]
          show_failure_change stat
        else
          show_perf_change stat
        end
        printf "  %s\n", stat[GROUP].axes.values.join('/')
      end
    end
  end

  ## Helper functions

  def self.commits_comparer(commits, params = nil)
    git = axis_key_git COMMIT_AXIS_KEY
    commits = git.sort_commits commits
    _result_roots = commits.map do |c|
      MResultRootCollection.new(COMMIT_AXIS_KEY => c.to_s).to_a
    end.flatten
    compare_axis_keys = [COMMIT_AXIS_KEY]
    comparer = Comparer.new
    comparer.set_mresult_roots(_result_roots)
            .set_sort_mresult_roots(false)
            .set_compare_axis_keys(compare_axis_keys)
            .apply_params(params)
  end

  def self.compare_commits(commits, params = nil)
    comparer = commits_comparer commits, params
    comparer.compare
  end

  def self.ncommits_comparer(commits, params = nil)
    git = axis_key_git COMMIT_AXIS_KEY
    commits = git.sort_commits commits
    _rts = commits.map do |c|
      NMResultRootCollection.new(COMMIT_AXIS_KEY => c.to_s).to_a
    end.flatten
    compare_axis_keys = [COMMIT_AXIS_KEY]
    comparer = Comparer.new
    comparer.set_mresult_roots(_rts)
            .set_sort_mresult_roots(false)
            .set_compare_axis_keys(compare_axis_keys)
            .apply_params(params)
  end

  def self.ncompare_commits(commits, params = nil)
    comparer = ncommits_comparer commits, params
    comparer.compare
  end

  def self.perf_comparer(commits, strict: false)
    ignored_testcases = Set.new %w[xfstests pts]
    git = axis_key_git COMMIT_AXIS_KEY
    commits = git.sort_commits commits
    _rts = commits.map do |c|
      DataStore::Collection.new(mrt_table_set.linux_perf_table, 'commit' => c.to_s).to_a
    end.flatten
    _rts.select! do |_rt|
      axes = _rt.axes
      testcase = axes[TESTCASE_AXIS_KEY]
      next false if ignored_testcases.member?(testcase)

      tbox = axes[TBOX_GROUP_AXIS_KEY]
      next false if tbox.start_with? 'vm-'

      true
    end
    compare_axis_keys = [COMMIT_AXIS_KEY]
    comparer = Comparer.new
    comparer.set_mresult_roots(_rts)
            .set_sort_mresult_roots(false)
            .set_compare_axis_keys(compare_axis_keys)
            .set_sort_by_group(true)
            .set_compact_show(true)
    if strict
      comparer.set_filter_kpi_stat_strict_keys(true)
    else
      comparer.set_filter_kpi_stat_keys(true)
    end
  end

  def self.perf_compare(commits)
    comparer = perf_comparer commits
    comparer.compare
  end

  def self.parse_argv(argv)
    options = {
      compare_axis_keys: [COMMIT_AXIS_KEY]
    }
    msearch_axes = []
    job_dirs = []
    opt_parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ncompare [options] <commit>...
       ncompare [options] -s <axes> [-s <axes>] [-o <axes>]'
      opts.separator ''
      opts.separator 'options:'

      opts.on('-c <compare_axis_keys>',
              '--compare-axis-keys <compare_axis_keys>',
              'Compare Axis keys') do |compare_axis_keys|
        options[:compare_axis_keys] = compare_axis_keys.split(',')
      end

      opts.on('-s <search-axes>', '--search <search-axes>',
              'Search Axes') do |search_axes|
        msearch_axes << DataStore::Layout.axes_from_string(search_axes)
      end

      opts.on('-o <search-axes>', '--override-search <search-axes>',
              'Search Axes') do |search_axes|
        search_axes = DataStore::Layout.axes_from_string(search_axes)
        options[:compare_different_rts] = true if search_axes.many?
        prev_axes = msearch_axes[-1] || {}
        msearch_axes << prev_axes.merge(search_axes)
      end

      opts.on('-j <job dir>', '--job-dir <job dir>', 'Job Directory') do |jd|
        job_dirs << jd
      end

      opts.on('-m', '--more', 'more stats as compare result') do
        options[:more_stats] = true
      end

      opts.on('-p <value>', '--perf-profile-threshold=<value>', 'perf-profile compare threshold') do |val|
        options[:perf_profile_threshold] = val.to_f
      end

      opts.on('-a', '--all', 'compare all stats') do
        options[:use_all_stat_keys] = true
      end

      opts.on('-k', '--kpi', 'compare kpi stats only') do
        options[:filter_kpi_stat_keys] = true
      end

      opts.on_tail('-h', '--help', 'Show this message') do
        puts opts
        return nil
      end
    end
    argv = ['-h'] if argv.empty?
    argv = opt_parser.parse(argv)

    if job_dirs.empty?
      if msearch_axes.empty?
        msearch_axes = argv.map do |c|
          { COMMIT_AXIS_KEY => c.to_s }
        end
      end
      _rts = msearch_axes.map do |axes|
        axes = axes_gcommit axes
        NMResultRootCollection.new(axes).to_a
      end.flatten
    else
      job_name = '*.yaml'
      if job_dirs.many?
        options[:compare_different_rts] = true
        job_name = 'job.yaml'
      end
      _rts = job_dirs.map do |job_dir|
        each_job_in_dir(job_dir, job_name).map do |job|
          mrt_table_set.open_node job.axes
        end
      end.flatten
      _rts.select!(&:exist?)

      if _rts.uniq.size == 1
        path = _rts.first.mresult_root_path
        options[:compare_runs] = job_dirs.filter_map do |job_dir|
          dir = job_dir.sub(/\/$/, '')
          "#{path}/#{dir.split('/').last}" == File.realpath(dir) ? dir.split('/').last : nil
        end
      end
    end
    options[:mresult_roots] = _rts
    options
  end

  def self.compare(argv)
    options = parse_argv argv
    return unless options

    comparer = Comparer.new options
    comparer.compare
  end

  ## Test functions

  def self.test_compare_commits
    commits = %w[f5c0a122800c301eecef93275b0c5d58bb4c15d9 3a8b36f378060d20062a0918e99fae39ff077bf0]
    comparer = commits_comparer commits
    comparer.set_compare_axis_keys([COMMIT_AXIS_KEY, 'rwmode'])
            .set_use_all_stats(false)
            .set_group_by_stat(false)

    pager do
      comparer.compare
    end
  end

  def self.test_incomplete_run
    _rt = "#{RESULT_ROOT_DIR}/lkp-sb02/sysbench-fileio/performance-600s-100%-1HDD-ext4-64G-1024f-seqrd-sync/debian-x86_64-2015-02-07.cgz/x86_64-rhel/"
    _rts = %w[9eccca0843205f87c00404b663188b88eb248051 06e5801b8cb3fc057d88cb4dc03c0b64b2744cda]
           .map { |c| MResultRoot.new(_rt + c) }
    _rts.each do |_rt|
      puts _rt.runs
    end
    comparer = Comparer.new
    comparer.set_mresult_roots(_rts)
            .set_compare_axis_keys([COMMIT_AXIS_KEY])
            .set_use_all_stats(false)
    page do
      comparer.compare
    end
  end

  def self.test_compare_aim7
    _result_roots = MResultRootCollection.new(
      COMMIT_AXIS_KEY => '39a8804455fb23f09157341d3ba7db6d7ae6ee76',
      'tbox_group' => 'grantley',
      'test' => 'ram_copy'
    ).to_a
    compare_axis_keys = ['load']
    comparer = Comparer.new
    comparer.set_mresult_roots(_result_roots)
            .set_compare_axis_keys(compare_axis_keys)
    pager do
      comparer.compare
    end
  end
end
