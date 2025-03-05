LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'time'

require "#{LKP_SRC}/lib/string"
require "#{LKP_SRC}/lib/common"
require "#{LKP_SRC}/lib/property"
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/result"
require "#{LKP_SRC}/lib/nresult_root"
require "#{LKP_SRC}/lib/constant"

def rt_create_time_from_job(job)
  end_time = job['end_time']
  if end_time
    Time.at(end_time.to_i)
  else
    job['dequeue_time']
  end
end

class ResultRoot < CResultRoot
  JOB_FILE = 'job.yaml'.freeze

  include Property
  prop_reader :axes

  private

  def initialize(path)
    super(path)

    @axes = calc_axes
  end

  def calc_axes
    as = job.axes
    rp = ResultPath.parse(@path)
    as['run'] = rp['run']
    as
  end

  public

  def axes_path
    as = deepcopy(@axes)
    as['path_params'] = job.path_params
    as
  end

  def job
    @job ||= Job.open path(JOB_FILE)
  end

  def calc_desc
    m = {}
    j = job
    %w[queue job_state].each do |k|
      m[k] = j[k]
    end
    m['create_time'] = rt_create_time_from_job j
    m
  end

  def desc
    @desc ||= calc_desc
  end

  def _result_root_path
    rp = ResultPath.parse(@path)
    rp._result_root
  end

  def _result_root
    MResultRoot.new _result_root_path
  end

  def collection
    ResultRootCollection.new axes_path
  end
end

# Minimal implementation just for convert to general data store
class ResultRootCollection
  include Enumerable

  attr_writer :date_glob, :queue

  def initialize(conditions = {})
    @conditions = conditions
    @date_glob = nil
  end

  def set(key, value)
    @conditions[key] = value
    self
  end

  def unset(key)
    @conditions.delete key
    self
  end

  def apply_date(time)
    @date_glob = str_date(time)
  end

  def each
    return enum_for(__method__) unless block_given?

    date_glob = @date_glob || DATE_GLOB
    files = Dir[File.join KTEST_PATHS_DIR, date_glob, "#{date_glob}-*"]
    files.sort!
    files.reverse!
    files.each do |fn|
      File.open(fn) do |f|
        f.readlines.reverse!.each do |rtp|
          # f.readlines.each { |rtp|
          rtp = rtp.strip
          next unless File.exist? rtp

          yield ResultRoot.new rtp
        end
      end
    end
  end
end

class Completion
  def initialize(line)
    fields = line.split
    @time = fields[0..2].join(' ').to_time
    @_rt = MResultRoot.new fields[4]
    @status = fields.drop(4).join ' '
  end

  attr_reader :time, :status

  def to_s
    "#{@time} #{@_rt} #{@status}"
  end
end

# Result root for multiple runs of a job
# M here stands for multiple runs
# _rt or mrt may be used as variable name
class MResultRoot
  COMPLETIONS_FILE = 'completions'.freeze
  MATRIX = 'matrix.json'.freeze

  def initialize(path)
    @path = path
    @path.freeze
    @axes = calc_axes
  end

  include DirObject
  include CMResultRoot

  attr_reader :axes

  def to_s
    @path
  end

  def calc_axes
    if job_file
      job.axes
    else
      rp = ResultPath.parse @path
      Hash[rp.to_a]
    end
  end

  def eql?(other)
    @axes.eql?(other.axes)
  end

  def hash
    @axes.hash
  end

  def axes_path
    as = deepcopy(@axes)
    if job_file
      path_params = job.path_params
    else
      rp = ResultPath.parse @path
      path_params = rp['path_params']
    end
    as['path_params'] = path_params
    as
  end

  def goto_commit(commit, commit_axis_key = 'commit')
    rp = ResultPath.parse @path

    rp[commit_axis_key] = commit
    _rtp = rp._result_root
    MResultRoot.new _rtp if File.exist? _rtp
  end

  def result_roots
    result_root_paths.map do |p|
      ResultRoot.new p
    end
  end

  def collection
    MResultRootCollection.new axes_path
  end

  def boot_collection
    bc = collection.unselect('path_params', 'rootfs')
    bc.testcase = 'boot'
    bc
  end

  def matrix_file
    path(MATRIX)
  end

  def matrix
    m = try_load_json matrix_file
    matrix_fill_missing_zeros m if m
  end

  def completions
    File.open(COMPLETIONS_FILE, 'r') do |f|
      f.each_line
       .map { |line| Completion.new line }
       .sort_by { |cmp| -cmp.time.to_i }
    end
  rescue Errno::ENOENT
    []
  end

  def calc_create_time
    (job_file && rt_create_time_from_job(job)) ||
      glob('*').map { |f| File.mtime f }.min
  end

  def calc_desc
    {
      DataStore::CREATE_TIME => calc_create_time
    }
  end

  def desc
    @desc ||= calc_desc
  end
end

class << MResultRoot
  def valid?(path)
    return true if File.exist? File.join(path, self::JOB_FILE1)
    return false unless File.exist? path

    Dir[File.join path, self::JOB_GLOB].first
  end

  def from_nmresult_root(nmresult_root)
    new nmresult_root.mresult_root_path
  end
end

class MResultRootCollection
  def initialize(conditions = {})
    cond = deepcopy(conditions)
    ResultPath::MAXIS_KEYS.each do |f|
      set_prop f, conditions[f]
      cond.delete f
    end
    @other_conditions = cond
  end

  include Property
  include Enumerable

  prop_with(*ResultPath::MAXIS_KEYS)

  def pattern
    result_path = ResultPath.new
    ResultPath::MAXIS_KEYS.each do |k|
      result_path[k] = get_prop(k) || '.*'
    end
    result_path._result_root
  end

  def each
    return enum_for(__method__) unless block_given?

    cmdline = "grep -he '#{pattern}' #{KTEST_PATHS_DIR}/*/????-??-??-*"
    @other_conditions.each_value do |ocond|
      cmdline += " | grep -e '#{ocond}'"
    end
    cmdline += " | sed -e 's#[0-9]\\+/$##' | sort | uniq"
    IO.popen(cmdline) do |io|
      io.each_line do |_rtp|
        _rtp = _rtp.strip
        yield MResultRoot.new _rtp.strip if MResultRoot.valid? _rtp
      end
      Process.waitpid io.pid
    end
  end

  def select(field, value)
    field = field.to_s
    value = value.to_s
    if ResultPath::MAXIS_KEYS.index field
      set_prop(field, value)
    else
      @other_conditions[field] = value
    end
    self
  end

  def unselect(*fields)
    fields.each do |f|
      f = f.to_s
      if ResultPath::MAXIS_KEYS.index f
        set_prop(f, nil)
      else
        @other_conditions.delete f
      end
    end
    self
  end
end

def convert_one_mresult_root(_rt)
  mrtts = mrt_table_set
  n = mrtts.new_node(_rt.axes)
  if File.symlink?(n.path) && File.readlink(n.path) == _rt
    false
  else
    n.create_storage_link(_rt.path)
    n.update_desc do |desc|
      desc.update(_rt.desc)
    end
    n.index(force: true)
    true
  end
end

def create_mresult_root_tables
  MResultRootTableSet.create_tables_layout(force: true)
end

def convert_all_mresult_root(date_from_in = nil, date_to_in = nil)
  rtc = ResultRootCollection.new
  date = date_of_time date_from_in
  date_to = date_of_time date_to_in
  n = 0
  while date <= date_to
    rtc.apply_date(date)
    rtc.each do |rt|
      n += 1
      _rt = rt._result_root
      puts "#{n}: #{_rt}" if convert_one_mresult_root(_rt)
    end
    date += ONE_DAY
  end
end

def mrt_storage_path(_rt_path)
  _rt = MResultRoot.new(_rt_path)
  mrtts = mrt_table_set
  n = mrtts.new_node(_rt.axes)
  n.path
end

def convert_mrt(_rt_path)
  _rt = MResultRoot.new(_rt_path)
  convert_one_mresult_root(_rt)
end

def delete_mrt(_rt_path)
  mrtts = mrt_table_set
  _rt = MResultRoot.new(_rt_path)
  n = mrtts.open_node(_rt.axes)
  n.delete if File.exist? n.path
end

def save_mrt_result_stddev(_rt_path)
  _rt = MResultRoot.new(_rt_path)
  ResultStddev.save(_rt)
end
