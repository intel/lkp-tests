LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/common"
require "#{LKP_SRC}/lib/property"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/job"
require "#{LKP_SRC}/lib/result"
require "#{LKP_SRC}/lib/data_store"
require "#{LKP_SRC}/lib/matrix"
require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/constant"

# Common Result Root
# to share code between original ResultRoot and NResultRoot
class CResultRoot
  # TODO: remove .dmesg after we convert all .dmesg to dmesg
  DMESG_FILES = ['dmesg.xz', 'dmesg', '.dmesg', 'kmsg.xz', 'kmsg'].freeze
  DMESG_JSON_FILE = 'dmesg.json'.freeze
  KMSG_JSON_FILE = 'kmsg.json'.freeze
  MATRIX_FILE = 'matrix.json'.freeze

  include DirObject

  def initialize(path)
    @path = path
    @path.freeze
  end

  def dmesg_json_file
    fn = path(DMESG_JSON_FILE)
    fn if File.exist?(fn)
  end

  def dmesg_json
    fn = dmesg_json_file
    load_json(fn) if fn
  end

  def kmsg_json_file
    fn = path(KMSG_JSON_FILE)
    fn if File.exist?(fn)
  end

  def kmsg_json
    fn = kmsg_json_file
    load_json(fn) if fn
  end

  def dmesg_file
    DMESG_FILES.each do |fn|
      ffn = path fn
      return ffn if File.exist? ffn
    end
    nil
  end

  def matrix_file
    path(MATRIX_FILE)
  end

  def matrix
    try_load_json matrix_file
  end
end

# Common Multiple Result Root
#   to share code between original MResultRoot and NMResultRoot
module CMResultRoot
  DMESG_GLOBS = CResultRoot::DMESG_FILES.map { |g| "[0-9]*/#{g}" }
  DMESG_JSON_GLOB = '[0-9]*/dmesg.json'.freeze
  JOB_GLOB = '[0-9]*/job.yaml'.freeze
  JOB_FILE1 = 'job.yaml'.freeze
  REPRODUCE_GLOB = '[0-9]*/reproduce.sh'.freeze

  def dmesgs
    DMESG_GLOBS.each do |g|
      dmesgs = glob(g)
      return dmesgs unless dmesgs.empty?
    end
    []
  end

  def dmesg_jsons
    glob DMESG_JSON_GLOB
  end

  def job_file
    job1 = path(JOB_FILE1)
    return job1 if File.exist? job1

    jobs = glob(JOB_GLOB)
    jobs[0] unless jobs.empty?
  end

  def job
    Job.open job_file
  end

  def reproduce_file
    reproduce_files = glob(REPRODUCE_GLOB)
    reproduce_files[0] unless reproduce_files.empty?
  end

  def result_root_paths
    glob(JOB_GLOB).map do |jfn|
      File.dirname jfn
    end
  end

  def complete_matrix(m = nil)
    m ||= matrix
    if m['last_state.is_incomplete_run']
      m = deepcopy(m)
      filter_incomplete_run m
    end
    m
  end

  def runs(m = nil)
    m ||= matrix
    return 0, 0 unless m

    all_runs = matrix_cols m
    cm = complete_matrix m
    complete_runs = matrix_cols cm
    [all_runs, complete_runs]
  end

  def result_roots_with_stat(stat)
    result_roots.select do |rt|
      (m = rt.matrix) && m[stat]
    end
  end

  def kpi_avg_stddev
    cm = complete_matrix
    return if matrix_cols(cm) < 3

    avg_stddev = {}
    cm.each do |k, v|
      next unless kpi_stat?(k, axes, [v])

      avg_stddev[k] = [v.average, v.standard_deviation]
    end
    avg_stddev
  end

  ResultPath::MAXIS_KEYS.each do |k|
    define_method(k.intern) { @axes[k] }
  end
end

class NResultRoot < CResultRoot
end

class NMResultRoot < DataStore::Node
  include CMResultRoot

  def matrix
    matrix_fill_missing_zeros(super)
  end

  def result_roots
    result_root_paths.map do |p|
      NResultRoot.new p
    end
  end

  def collection
    NMResultRootCollection.new axes
  end

  def goto_commit(commit, commit_axis_key = 'commit')
    c = collection
    c.set(commit_axis_key, commit)
    c.to_a.first
  end

  def mresult_root_path
    File.readlink @path
  end

  def to_data
    axes
  end

  class << self
    def from_data(data)
      mrt_table_set.open_node data
    end
  end
end

# Multiple "Multiple Result Root (_rt)"
class MMResultRoot
  def initialize
    @mresult_roots = []
  end

  def add_mresult_root(_rt)
    @mresult_roots << _rt
  end

  def matrix
    merge_matrixes(@mresult_roots.map { |_rt| _rt.matrix if _rt })
  end

  def complete_matrix(m = nil)
    m ||= matrix
    if m['last_state.is_incomplete_run']
      m = deepcopy(m)
      filter_incomplete_run m
    end
    m
  end

  def axes
    @mresult_roots.first.axes
  end
end

class MResultRootTable < DataStore::Table
  MRESULT_ROOT_DIR = File.join KTEST_DATA_DIR, 'mresult_root'

  def initialize(layout)
    super
    @node_class = NMResultRoot
  end
end

class << MResultRootTable
  def table_dir(name)
    File.join self::MRESULT_ROOT_DIR, name
  end

  def create_layout(name, force: false)
    dir = table_dir name
    return if !force && DataStore::Layout.exist?(dir)

    FileUtils.rm_rf(dir)
    layout = DataStore::Layout.create_new dir
    layout.save
    layout.add_index DataStore::DateIndex
    layout
  end

  def open(name)
    super table_dir(name)
  end
end

class LinuxMResultRootTable < MResultRootTable
end

class << LinuxMResultRootTable
  def create_layout(name, force: false)
    layout = super
    if layout
      layout.add_index(DataStore::AxisIndex, 'commit') do |index|
        index.set_axis_keys ['commit']
      end
    end
    layout
  end
end

class MResultRootTableSet
  attr_reader :linux_perf_table

  LINUX_PERF_TABLE = 'linux_perf'.freeze
  LINUX_TABLE = 'linux'.freeze
  OTHER_TABLE = 'other'.freeze
  LINUX_PERF_TESTCASES = LinuxTestcasesTableSet::LINUX_PERF_TESTCASES
  LINUX_TESTCASES = LinuxTestcasesTableSet::LINUX_TESTCASES
  OTHER_TESTCASES = LinuxTestcasesTableSet::OTHER_TESTCASES

  def initialize
    @linux_perf_table = LinuxMResultRootTable.open(LINUX_PERF_TABLE)
    @linux_table = LinuxMResultRootTable.open(LINUX_TABLE)
    @other_table = MResultRootTable.open(OTHER_TABLE)

    @table_map = {
      LINUX_PERF_TABLE => @linux_perf_table,
      LINUX_TABLE => @linux_table,
      OTHER_TABLE => @other_table
    }

    @testcase_map = {}
    LINUX_PERF_TESTCASES.each do |c|
      @testcase_map[c] = @linux_perf_table
    end
    LINUX_TESTCASES.each do |c|
      @testcase_map[c] = @linux_table
    end
    OTHER_TESTCASES.each do |c|
      @testcase_map[c] = @other_table
    end
  end

  def testcase_to_table(testcase)
    testcase = testcase.sub(/^kvm:/, '')
    tbl = @testcase_map[testcase]
    raise "Unknow testcase: #{testcase}" unless tbl

    tbl
  end

  def tables
    [@linux_perf_table, @linux_table, @other_table]
  end

  def axes_to_table(axes)
    testcase_to_table(axes[TESTCASE_AXIS_KEY])
  end

  def new_node(axes)
    tbl = axes_to_table axes
    tbl.new_node axes
  end

  def open_node(axes)
    tbl = axes_to_table axes
    tbl.open_node axes
  end

  def open_node_from_omrt(omrt)
    open_node omrt.axes
  end

  def open_node_from_omrt_dir(omrt_dir)
    omrt = MResultRoot.new(omrt_dir)
    open_node_from_omrt omrt
  end

  class << self
    def create_tables_layout(force: false)
      MResultRootTable.create_layout(OTHER_TABLE, force: force)
      LinuxMResultRootTable.create_layout(LINUX_TABLE, force: force)
      LinuxMResultRootTable.create_layout(LINUX_PERF_TABLE, force: force)
    end
  end
end

def mrt_table_set
  $mrt_table_set ||= MResultRootTableSet.new
end

class NMResultRootCollection
  def initialize(conditions = {})
    @conditions = {}
    conditions.each do |k, v|
      @conditions[k] = v.to_s
    end
    @date = nil
    @exact = false
  end

  include Enumerable
  include Property

  prop_accessor :exact

  def set(key, value)
    @conditions[key] = value.to_s
    self
  end

  def unset(key)
    @conditions.delete key
    self
  end

  attr_writer :date

  def each(&b)
    return enum_for(__method__) unless block_given?

    table_each = lambda do |tbl|
      col = DataStore::Collection.new tbl, @conditions
      col.date = @date
      col.set_exact(@exact)
      col.each(&b)
    end

    testcase = @conditions[TESTCASE_AXIS_KEY]
    if testcase
      tbl = mrt_table_set.testcase_to_table testcase
      table_each.call(tbl)
    else
      mrt_table_set.tables.each do |tbl|
        table_each.call(tbl)
      end
    end
  end
end

def nmresult_root_collections_for_axis(_rt, axis_key, values)
  axes = _rt.axes
  values.map do |v|
    c = NMResultRootCollection.new axes
    c.set(axis_key, v.to_s).set_exact(true)
  end
end

def nresult_root_fsck
  col = NMResultRootCollection.new
  col.each do |mrt|
    puts mrt.path
    if Dir.exist?(mrt.path)
      yield(mrt) if block_given?
    else
      mrt.delete
    end
  end
end

module ResultStddev
  BASE_DIR = File.join(KTEST_DATA_DIR, 'result_stddev').freeze
  SOURCE_KEY = 'stat_source'.freeze
  DATA_NR_MAX = 5

  module_function

  # FIXME: Only Linux is supported
  def path(axes)
    caxes = deepcopy axes
    caxes.delete COMMIT_AXIS_KEY
    tbox = caxes[TBOX_GROUP_AXIS_KEY] || '-'
    hash = DataStore::Layout.axes_hash(caxes)
    dir = File.join(BASE_DIR, tbox)
    file = "#{hash}.json"
    [dir, file]
  end

  def delete_col(data, col)
    dkeys = []
    data.each do |k, vs|
      vs.delete_at col
      dkeys << k if vs.compact.empty?
    end
    dkeys.each do |k|
      data.delete k
    end
  end

  def save(_rt)
    axes = _rt.axes
    commit = axes[COMMIT_AXIS_KEY]
    return unless commit

    testcase = axes[TESTCASE_AXIS_KEY]
    return unless MResultRootTableSet::LINUX_PERF_TESTCASES.index testcase

    # Only save for release tags
    proj = 'linux'
    git = Git.open(project: proj, working_dir: ENV['SRC_ROOT'])
    return unless git.gcommit(commit).release_tag

    avg_stddev = _rt.kpi_avg_stddev
    return unless avg_stddev

    dir, file = ResultStddev.path axes
    FileUtils.mkdir_p dir
    path = File.join(dir, file)
    data = if File.exist? path
             load_json(path) || {}
           else
             {}
           end

    sources = data[SOURCE_KEY] || []
    source_str = DataStore::Layout.axes_to_string(axes)
    idx = sources.index source_str
    delete_col(data, idx) if idx
    delete_col(data, 0) if sources.size >= DATA_NR_MAX

    avg_stddev.each do |k, v|
      data[k] = [nil] * sources.size unless data[k]
      data[k] << v
    end
    sources << source_str
    data[SOURCE_KEY] = sources
    data.each_value do |vs|
      vs << nil if vs.size < sources.size
    end

    save_json data, path
  end

  def load(axes)
    dir, file = ResultStddev.path axes
    path = File.join dir, file
    return unless File.exist? path

    load_json path
  end

  def load_values(axes)
    data = load(axes)
    return unless data && !data.empty?

    data.delete SOURCE_KEY
    data.each do |k, vs|
      vs.compact!
      avgs, stddevs = vs.first.zip(*vs.drop(1))
      data[k] = [avgs.average, stddevs.average]
    end
    data
  end
end
