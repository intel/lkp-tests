#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'English'
require 'fileutils'
require 'json'
require 'yaml'
require "#{LKP_SRC}/lib/assert"
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/common"
require "#{LKP_SRC}/lib/erb"
require "#{LKP_SRC}/lib/log"

def compress_file(file)
  system "gzip #{file} < /dev/null"
end

def expand_yaml_template(yaml, file, context_hash = {})
  yaml = yaml_merge_included_files(yaml, File.dirname(file))
  yaml = literal_double_braces(yaml)
  expand_erb(yaml, context_hash)
end

# template_context should be nil or Hash
def load_yaml(file, template_context = nil)
  yaml = File.read file
  yaml = expand_yaml_template(yaml, file, template_context) if template_context

  begin
    result = YAML.unsafe_load(yaml)
  rescue Psych::SyntaxError => e
    log_debug "failed to parse file #{file} | #{e}"
    raise
  end

  assert result, "possible empty file #{file} #{File.size file}" unless template_context

  result
end

def load_yaml_with_flock(file, timeout = nil)
  with_flock("#{file}.lock", timeout) do
    load_yaml file
  end
end

def load_yaml_merge(files)
  all = {}
  files.each do |file|
    next unless File.size? file

    begin
      yaml = load_yaml(file)
      all.update(yaml)
    rescue StandardError => e
      log_warn "#{e.class.name}: #{e.message.split("\n").first}: #{file}"
    end
  end
  all
end

def load_yaml_tail(file)
  begin
    stdout = Bash.run('tail', '-n', '100', file)
    return YAML.unsafe_load(stdout)
  rescue Bash::BashCallError
    nil
  rescue Psych::SyntaxError => e
    log_warn "#{file}: " + e.message
  end
  nil
end

def search_file_in_paths(file, relative_to = nil, search_paths = nil)
  if file[0] == '/'
    return unless File.exist? file

    return file
  end

  relative_to ||= Dir.pwd

  if file =~ /^\.\.?\//
    file = File.join(relative_to, file)
    return unless File.exist? file

    return file
  end

  search_paths ||= [File.dirname(__FILE__, 2)]
  search_paths.unshift(relative_to)

  search_paths.each do |search_path|
    path = File.join(search_path, file)
    return path if File.exist? path
  end
  nil
end

def parse_include_content(content)
  begin
    args = eval("[#{content}]")
  rescue SyntaxError, NameError
    # Support unquoted filenames (e.g. "file.yaml, ignore: keys")
    # by quoting the part before the first comma.
    begin
      if (comma_index = content.index(','))
        file_part = content[0...comma_index].strip
        rest_part = content[comma_index..]
        args = eval("['#{file_part}'#{rest_part}]")
      else
        args = [content.strip]
      end
    rescue SyntaxError, NameError
      return [content, []]
    end
  end

  return [content, {}] unless args.is_a?(Array) && args.first.is_a?(String)

  file = args[0]
  options = args[1]
  options = {} unless options.is_a?(Hash)
  [file, options]
end

def yaml_merge_included_files(yaml, relative_to, search_paths = nil)
  yaml.gsub(/(.*)<< *: +([^*\[].*)/) do |_match|
    prefix = $1
    content = $2.chomp

    file, options = parse_include_content(content)
    ignore_keys = options[:ignore] ? Array(options[:ignore]).map(&:to_s) : []
    # Any option other than :ignore is treated as a key override to be appended
    overrides = options.except(:ignore)

    path = search_file_in_paths file, relative_to, search_paths
    raise "included yaml file not found | file: #{file}, relative_to: #{relative_to}, search_paths: #{search_paths}" unless path

    to_merge = File.read path

    to_merge = to_merge.lines.grep_v(/^(#{ignore_keys.join('|')})\s*:/).join if ignore_keys.any?

    overrides.each do |key, value|
      # Append overrides at the correct indentation level
      # Dump the value to YAML to handle quoting/types.
      # YAML.dump(val) returns "---\nval\n", so we strip "--- " prefix or "---\n" prefix and the trailing newline.
      yaml_val = YAML.dump(value).sub(/\A---\s*\n?/, '').chomp
      pattern = /^(#{Regexp.escape(key)})\s*:\s+.*$/

      if to_merge.match?(pattern)
        to_merge = to_merge.gsub(pattern, "#{key}: #{yaml_val}")
      else
        to_merge += "\n#{key}: #{yaml_val}"
      end
    end

    indent = prefix.tr '^ ', ' '
    indented = [prefix]
    to_merge.split("\n").each do |line|
      indented << if line =~ /^%([!%]*)$/
                    "%#{indent}#{line[1..]}"
                  else
                    indent + line
                  end
    end

    indented.join("\n")
  end
end

def dot_file(path)
  "#{File.dirname(path)}/.#{File.basename(path)}"
end

def save_yaml(object, file, compress: false)
  temp_file = File.join('/tmp', ".#{File.basename(file)}-#{tmpname}")
  File.write(temp_file, YAML.dump(object))
  FileUtils.mv temp_file, file, force: true

  return unless compress

  FileUtils.rm "#{file}.gz", force: true
  compress_file(file)
end

def save_yaml_with_flock(object, file, timeout = nil, compress: false)
  with_flock("#{file}.lock", timeout) do
    save_yaml object, file, compress: compress
  end
end

$json_cache = {}
$json_mtime = {}

def load_json(file, cache: false)
  file += '.gz' if file =~ /.json$/ && File.exist?("#{file}.gz")
  if file =~ /.json(\.gz)?$/ && File.exist?(file)
    begin
      mtime = File.mtime(file)
      unless $json_cache[file] && $json_mtime[file] == mtime
        obj = if file =~ /\.json$/
                JSON.parse File.read(file, encoding: 'UTF-8')
              else
                JSON.parse Bash.run("zcat #{file}")
              end
        return obj unless cache

        $json_cache[file] = obj
        $json_mtime[file] = mtime
      end
      return $json_cache[file].freeze
    rescue SignalException
      raise
    rescue StandardError
      log_warn "Failed to load JSON file: #{file}"

      tempfile = "#{file}-bad"
      log_debug "Kept corrupted JSON file for debugging: #{tempfile}"
      FileUtils.mv file, tempfile, force: true

      raise
    end
    nil
  elsif File.exist? file.sub(/\.json(\.gz)?$/, '.yaml')
    load_yaml file.sub(/\.json(\.gz)?$/, '.yaml')
  else
    log_debug "JSON/YAML file not exist: '#{file}'"
    nil
  end
end

def save_json(object, file, compress: false)
  temp_file = dot_file(file) + "-#{tmpname}"
  File.write(temp_file, JSON.pretty_generate(object, allow_nan: true))
  FileUtils.mv temp_file, file, force: true

  return unless compress

  FileUtils.rm "#{file}.gz", force: true
  compress_file(file)
end

def try_load_json(path)
  if File.file? path
    load_json(path)
  elsif path =~ /.json$/
    if File.file? "#{path}.gz"
      load_json("#{path}.gz")
    elsif File.file? path.sub(/\.json$/, '.yaml')
      load_json(path)
    end
  end
end

class JSONFileNotExistError < StandardError
  def initialize(path)
    super("Failed to load JSON for #{path}")
    @path = path
  end

  attr_reader :path
end

def load_merge_jsons(path)
  return unless path.index(',')

  files = path.split(',')
  files.each do |file|
    return nil unless File.exist? file
  end

  matrix_from_stats_files(files)
end

def search_load_json(path)
  try_load_json(path) ||
    try_load_json("#{path}/matrix.json") ||
    try_load_json("#{path}/stats.json") ||
    load_merge_jsons(path) ||
    raise(JSONFileNotExistError, path)
end

def search_json(path)
  search_load_json path
rescue JSONFileNotExistError
  false
end

def load_regular_expressions(file, options = {})
  pattern = File.read(file).split("\n")
  spec = "#{options[:prefix]}(#{pattern.join('|')})#{options[:suffix]}"
  Regexp.new spec
end
