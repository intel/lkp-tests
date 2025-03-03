LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'digest/sha1'
require 'fileutils'

require "#{LKP_SRC}/lib/common"
require "#{LKP_SRC}/lib/property"
require "#{LKP_SRC}/lib/yaml"

module DataStore
  CREATE_TIME = 'create_time'.freeze

  def self.normalize_axes(axes)
    naxes = {}
    axes.each do |k, v|
      naxes[k.to_s] = v.to_s
    end
    naxes
  end

  class Map
    NAME = :name
    AXIS_KEYS = :axis_keys
    SUPPRESS_LAST = :suppress_last
    PROPS = [NAME, AXIS_KEYS, SUPPRESS_LAST].freeze
    ALL_OTHERS_KEY = :__all_others__

    include Property
    prop_accessor(*PROPS)

    def initialize(params)
      from_data params
    end

    def from_data(params)
      PROPS.each do |k|
        set_prop k, params[k]
      end
    end

    def to_data
      params = {}
      PROPS.each do |k|
        params[k] = get_prop k
      end
    end
  end

  class Layout
    CONFIG_FILE = 'layout.yaml'.freeze
    MATRIX_FILE = 'matrix.json'.freeze
    INDEX_DIR = 'index'.freeze
    INDEX_GLOB = "#{INDEX_DIR}/*".freeze
    MAPS = :maps
    COMPRESS_MATRIX = :comrpess_matrix

    include DirObject

    prop_reader :maps
    prop_accessor :compress_matrix

    def initialize(path, create_new: false)
      @path = path
      if create_new
        @maps = []
      else
        load
      end
    end

    private

    def load
      begin
        elayout = load_yaml path(CONFIG_FILE)
      rescue StandardError
        elayout = {}
      end
      from_data elayout
    end

    def from_data(elayout)
      @maps = []
      elayout[MAPS].each do |em|
        add_map(em)
      end
      @compress_matrix = elayout[COMPRESS_MATRIX]
    end

    def to_data
      {
        MAPS => @maps.map(&:to_data),
        COMPRESS_MATRIX => @comparess_matrix
      }
    end

    public

    def save
      mkdir_p @path
      elayout = to_data
      save_yaml elayout, path(CONFIG_FILE)
    end

    # storage

    def storage_hash_path(hash_str)
      path 'storage', hash_str[0...2], hash_str
    end

    def storage_path(axes)
      storage_hash_path Layout.axes_hash(axes)
    end

    def matrix_path(node)
      mf = MATRIX_FILE
      mf += '.gz' if @comparess_matrix
      node.path(mf)
    end

    # map

    def add_map(params)
      @maps << Map.new(params)
    end

    def map_dir(map, values)
      path 'maps', map.name, *values
    end

    def calc_all_others_map_value(axes, axes_keys)
      as = deepcopy(axes)
      axes_keys.each do |k|
        next if k == Map::ALL_OTHERS_KEY

        as.delete k
      end
      as.each.map do |k, v|
        "#{k}=#{v}"
      end.sort!.join('-')
    end

    def calc_map_dir(map, node)
      axes = node.axes
      map_values = map.axis_keys.map do |k|
        if k == Map::ALL_OTHERS_KEY
          calc_all_others_map_value axes, map.axis_keys
        else
          axes.fetch(k, '_').to_s
        end
      end
      map_dir(map, map_values)
    end

    def make_map(map, node)
      mdir = calc_map_dir map, node
      if map.suppress_last
        mkdir_p File.dirname(mdir)
        FileUtils.rm_rf mdir
      else
        mkdir_p mdir
      end
      make_relative_symlink(storage_path(node.axes), mdir)
    end

    def delete_map(map, node)
      mdir = calc_map_dir map, node
      mpath = if map.suppress_last
                mdir
              else
                File.join mdir, Layout.axes_hash(node.axes)
              end
      FileUtils.rm_f(mpath)
    end

    def map(node)
      @maps.each do |m|
        make_map(m, node)
      end
    end

    def unmap(node)
      @maps.each do |m|
        delete_map(m, node)
      end
    end

    # index

    def parse_index_path(dir)
      dir = File.basename dir
      n = dir.index '-'
      if n
        [dir[0, n], dir[n + 1...dir.size]]
      else
        [dir, nil]
      end
    end

    def cons_index_path(cls, name)
      base = if name && !name.empty?
               [cls.name, name].join '-'
             else
               cls.name
             end
      path INDEX_DIR, base
    end

    def load_indexes
      indexes = []
      glob(INDEX_GLOB) do |dir|
        if Dir.exist?(dir)
          cls_name, _name = parse_index_path dir
          cls = get_the_const(cls_name)
          indexes << cls.new(dir) if cls
        end
      end
      indexes
    end

    def add_index(cls, name = nil)
      dir = cons_index_path cls, name
      raise "Index already exist: #{dir}" if Dir.exist? dir

      index = cls.new(dir, create_new: true)
      yield index if block_given?
      index.save_config
    end
  end

  class << Layout
    private :new

    class << self
      include AddCachedMethod
    end
    add_cached_method :new

    def open(path)
      path = canonicalize_path path
      cached_new path, path
    end

    def create_new(path)
      path = canonicalize_path path
      cached_new path, path, create_new: true
    end

    def exist?(path)
      File.exist? File.join(path, self::CONFIG_FILE)
    end

    def node_dir_to_table_dir(node_dir)
      storage_dir = File.dirname(File.dirname(node_dir))
      if File.basename(storage_dir) == 'storage'
        File.dirname(storage_dir)
      elsif symlink? node_dir
        # symlink in maps
        target = File.readlink(node_dir)
        node_dir = File.join File.dirname(node_dir), target
        node_dir = canonicalize_path node_dir
        node_dir_to_table_dir node_dir
      end
    end

    def axes_to_string(axes)
      axes.each.map do |k, v|
        "#{k}=#{v}"
      end.sort!.join('/')
    end

    def axes_from_string(str)
      as = {}
      kvs = str.split '/'
      kvs.each do |kv|
        k, v = kv.split '='
        as[k] = v
      end
      as
    end

    def axes_str_hash(axes_str)
      Digest::SHA1.hexdigest axes_str
    end

    def axes_hash(axes)
      axes_str_hash axes_to_string(axes)
    end
  end

  class Index
    LOCK_FILE = '.lock'.freeze
    CONFIG_FILE = 'index.yaml'.freeze

    include DirObject

    def initialize(path, create_new: false)
      @path = path
      load_config unless create_new
    end

    def load_config
      data = load_yaml path(CONFIG_FILE)
      from_data data
    end

    def save_config
      data = to_data
      mkdir_p path
      save_yaml data, path(CONFIG_FILE)
    end

    def from_data(data); end

    def to_data
      {}
    end

    def with_index_lock(&blk)
      file = path(LOCK_FILE)
      begin
        with_flock(file, 1800, &blk)
      rescue Timeout::Error
        puts "with_index_lock timeout: #{file}"
      end
    end
  end

  module IndexFile
    def delete_str(str, file)
      str = Regexp.escape str
      system 'sed', '-i', '-re', "\\?#{str}?d", file
    end

    def grep(conditions, files)
      cond_arr = conditions.to_a
      k0, v0 = cond_arr[0]
      grep_cmdline = "grep -F -e '#{k0}=#{v0.to_s.empty? ? v0 : "#{v0}/"}'"
      ext_grep_cmdline = ''
      cond_arr.drop(1).each do |k, v|
        ext_grep_cmdline += " | grep -F -e '#{k}=#{v.to_s.empty? ? v : "#{v}/"}'"
      end

      files.each do |ifn|
        `strings #{ifn} | sed 's#$#/#' | #{grep_cmdline} #{ext_grep_cmdline}`.lines.reverse!.each do |line|
          line = line.strip.sub(/\/$/, '')
          yield line unless line.empty?
        end
      end
    end
  end

  class DateIndex < Index
    include IndexFile

    def score(_conditions)
      10
    end

    def index_file(date)
      path str_date(date)
    end

    def index(node)
      with_index_lock do
        File.open(index_file(node.create_time), 'a') do |f|
          str = Layout.axes_to_string node.axes
          f.write "#{str}\n"
        end
      end
    end

    def delete(node)
      with_index_lock do
        str = Layout.axes_to_string node.axes
        ifns = index_files node.create_time
        ifns.each do |ifn|
          delete_str str, ifn
        end
      end
    end

    def index_files(date = nil)
      if date
        fn = index_file date
        if File.exist? fn
          [fn]
        else
          []
        end
      else
        files = glob(DATE_GLOB)
        files.sort!
        files.reverse!
        files
      end
    end

    def each_for_all
      index_files.each do |ifn|
        File.open(ifn) do |f|
          f.readlines.reverse!.each do |line|
            line = line.strip
            yield line unless line.empty?
          end
        end
      end
    end

    def each(conditions, date = nil, &blk)
      return enum_for(__method__) unless block_given?

      if conditions.empty?
        each_for_all(&blk)
      else
        grep(conditions, index_files(date), &blk)
      end
    end
  end

  class AxisIndex < Index
    AXIS_KEYS = :axis_keys

    include Property
    include IndexFile

    prop_accessor AXIS_KEYS

    def from_data(data)
      @axis_keys = data[AXIS_KEYS]
    end

    def to_data
      {
        AXIS_KEYS => axis_keys
      }
    end

    def score(conditions)
      v = conditions[@axis_keys.first]
      if v && !v.empty?
        100
      else
        0
      end
    end

    def index_file(axes)
      bn = axes[@axis_keys.first]
      return unless bn

      path File.join(bn[0..1], bn)
    end

    def index(node)
      axes = node.axes
      ifn = index_file axes
      return unless ifn

      mkdir_p File.dirname(ifn) unless Dir.exist? File.dirname(ifn)

      with_index_lock do
        File.open(ifn, 'a') do |f|
          str = Layout.axes_to_string axes
          f.write "#{str}\n"
        end
      end
    end

    def delete(node)
      axes = node.axes
      ifn = index_file axes
      return unless ifn

      str = Layout.axes_to_string axes
      delete_str str, ifn
    end

    def each(conditions, _date = nil, &blk)
      return enum_for(__method__) unless block_given?

      ifn = index_file conditions
      return unless ifn
      return unless File.exist? ifn

      nconds = conditions.dup
      nconds.delete @axis_keys.first
      grep(conditions, [ifn], &blk)
    end
  end

  class Node
    AXES = :axes
    DESC = :desc
    STAT_KEY = :key
    STAT_VALUE = :value

    DESC_FILE = 'desc.yaml'.freeze
    START_INDEX_FILE = '.start_index'.freeze
    INDEXED_FILE = '.indexed'.freeze
    LOCK_FILE = '.lock'.freeze

    include DirObject
    prop_reader :table, :axes

    private

    def initialize(table)
      @table = table
    end

    def layout
      @table.layout
    end

    def __save_matrix(m)
      save_json m, layout.matrix_path(self)
    end

    def __save_desc(d)
      d[AXES] = @axes
      save_yaml d, path(DESC_FILE)
    end

    public

    def init_from_axes(axes)
      @axes = DataStore.normalize_axes(axes).freeze
      @path = layout.storage_path(@axes)
    end

    def init_from_path(dir)
      @path = dir
      d = load_yaml(path(DESC_FILE))
      @axes = d[AXES]
      @axes.freeze
    end

    def exist?
      Dir.exist? @path
    end

    def axes_hash
      Layout.axes_hash(axes)
    end

    def eql?(other)
      @axes.eql?(other.axes)
    end

    def hash
      @axes.hash
    end

    def matrix_file
      layout.matrix_path self
    end

    def matrix
      try_load_json(matrix_file) || {}
    end

    def save_matrix(m)
      mkdir_p @path
      with_flock(path(LOCK_FILE)) do
        __save_matrix m
      end
    end

    def update_matrix
      mkdir_p @path
      with_flock(path(LOCK_FILE)) do
        m = matrix
        yield m
        __save_matrix m
      end
    end

    def desc
      desc_file = path(DESC_FILE)
      d = if File.exist? desc_file
            load_yaml desc_file
          else
            {}
          end
      d[AXES] = @axes
      d
    end

    def save_desc(d)
      mkdir_p @path
      with_flock(path(LOCK_FILE)) do
        __save_desc d
      end
    end

    def update_desc
      mkdir_p @path
      with_flock(path(LOCK_FILE)) do
        d = desc
        yield d if block_given?
        __save_desc d
      end
    end

    def create_storage_link(src)
      mkdir_p File.dirname(@path)
      FileUtils.rm_f(@path)
      FileUtils.symlink(src, @path, force: true)
    end

    def calc_create_time
      files = Dir[path('*')]
      if files
        files.map { |f| File.mtime f }.sort!.first if files
      else
        Time.now
      end
    end

    def create_time
      unless @create_time
        d = desc
        @create_time = d[CREATE_TIME]
      end
      @create_time
    end

    def index(force: false)
      indexed_file = path(INDEXED_FILE)
      FileUtils.rm_f(indexed_file) if force
      indexed = File.exist? indexed_file
      return if indexed

      update_desc do |d|
        d[CREATE_TIME] ||= calc_create_time
      end

      FileUtils.touch path(START_INDEX_FILE)
      @table.index_node(self)
      FileUtils.touch indexed_file
    end

    def unindex
      indexed_file = path(INDEXED_FILE)
      @table.unindex_node(self)
      FileUtils.rm_f indexed_file
      FileUtils.rm_f path(START_INDEX_FILE)
    end

    def each
      return enum_for(__method__) unless block_given?

      as = @axes
      d = desc
      m = matrix

      m.each do |k, v|
        stat = {
          AXES => as,
          DESC => d,
          STAT_KEY => k,
          STAT_VALUE => v
        }
        yield stat
      end
    end

    def collection
      c = Collection.new(table, axes)
      c.date = create_time
      c
    end

    def delete
      unindex
      if File.symlink? @path
        FileUtils.rm_f @path
      else
        FileUtils.rm_rf @path
      end
    end
  end

  class << Node
    private :new

    def create_new(table, axes)
      n = new table
      n.init_from_axes axes
      n
    end

    def open(table, axes)
      n = new table
      n.init_from_axes axes
      n
    end

    def open_table_dir(table, dir)
      n = new table
      n.init_from_path dir
      n
    end

    def open_dir(dir)
      dir = canonicalize_path dir
      table = Table.open_from_node_dir dir
      open_table_dir table, dir
    end
  end

  class Collection
    include Enumerable
    include Property

    attr_writer :date

    def initialize(table, conditions = {})
      @table = table
      @conditions = {}
      conditions.each do |k, v|
        @conditions[k] = v.to_s
      end
      @date = nil
      @exact = false
    end

    prop_accessor :exact

    def set(key, value)
      @conditions[key] = value.to_s
      self
    end

    def unset(key, _value)
      @conditions.delete key
      self
    end

    def each
      return enum_for(__method__) unless block_given?

      if @exact
        node = @table.open_node @conditions
        yield node if node.exist?
        return
      end

      index = @table.find_best_index @conditions
      index.each(@conditions, @date) do |axes_str|
        node = @table.open_node_from_axes_str(axes_str)
        yield node
      end
    end

    def each_stat(&b)
      return enum_for(__method__) unless block_given?

      each do |n|
        n.each(&b)
      end
    end
  end

  class Table
    prop_reader :layout

    def initialize(layout)
      @node_class = Node
      @layout = layout
      @indexes = layout.load_indexes
    end

    def new_node(axes)
      @node_class.create_new self, axes
    end

    def open_node(axes)
      @node_class.open self, axes
    end

    def open_node_dir(dir)
      @node_class.open_table_dir self, dir
    end

    def open_node_from_axes_str(axes_str)
      open_node Layout.axes_from_string(axes_str)
    end

    def delete_node(node)
      node.delete
    end

    def index_node(node)
      @layout.map(node)
      @indexes.each do |idx|
        idx.index node
      end
    end

    def unindex_node(node)
      @layout.unmap(node)
      @indexes.each do |idx|
        idx.delete node
      end
    end

    def find_best_index(conditions)
      indexes = @indexes.dup
      indexes.sort_by! do |idx|
        idx.score(conditions)
      end
      indexes.last
    end

    def collection(conditions = {})
      Collection.new(self, conditions)
    end
  end

  class << Table
    private :new

    class << self
      include AddCachedMethod
    end
    add_cached_method :new

    def open(path)
      path = canonicalize_path path
      layout = Layout.open path
      cached_new path, layout
    end

    def open_from_node_dir(node_dir)
      node_dir = canonicalize_path node_dir
      path = Layout.node_dir_to_table_dir node_dir
      path = canonicalize_path path
      cached_new path, path
    end
  end

  def self.test
    tbl_path = File.join(ENV['HOME'], 'tbl1')
    FileUtils.rm_rf tbl_path
    layout = Layout.create_new tbl_path
    layout.add_map(Map::NAME => 'default',
                   Map::AXIS_KEYS => ['a', 'b', Map::ALL_OTHERS_KEY],
                   Map::SUPPRESS_LAST => true)
    layout.add_map(Map::NAME => 'c',
                   Map::AXIS_KEYS => ['c'])
    layout.save
    layout.add_index DateIndex
    layout.add_index(AxisIndex, 'a') do |index|
      index.set_axis_keys ['a']
    end
    tbl = Table.open tbl_path
    %w[
      1c163f4c7b3f621efff9b28a47abb36f7378d783
      e93c9c99a629c61837d5a7fc2120cd2b6c70dbdd
      0ecfebd2b52404ae0c54a878c872bb93363ada36
      4d856f72c10ecb060868ed10ff1b1453943fc6c8
    ].each do |a|
      'h'.upto('k') do |b|
        n = tbl.new_node('a' => a, 'b' => b, 'c' => 2)
        m = n.matrix
        m['s1'] = [1, 2, 3]
        m['s2'] = [4, a, b]
        n.save_matrix m
        n.index
      end
    end
    puts 'all nodes:'
    tbl.collection.each do |n|
      puts "  node: #{n.axes}: #{n.matrix}"
    end
    puts "collection: 'b' => 'i'"
    coll = Collection.new tbl, 'b' => 'i'
    coll.each_stat do |s|
      puts "  stat: #{s}"
    end
    tbl
  end
end
