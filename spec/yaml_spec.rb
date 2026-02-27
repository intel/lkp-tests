require 'spec_helper'
require 'timeout'
require "#{LKP_SRC}/lib/yaml"

TEST_YAML_FILE = '/tmp/test.yaml'.freeze

describe 'load_yaml_with_flock' do
  before do
    File.write(TEST_YAML_FILE, "key1: value1\nkey2: value2\n")
  end

  after do
    FileUtils.rm TEST_YAML_FILE
    FileUtils.rm "#{TEST_YAML_FILE}.lock"
  end

  it 'returns correct value' do
    yaml = load_yaml_with_flock TEST_YAML_FILE
    expect(yaml['key2']).to eq 'value2'
  end

  it 'raises Timeout Error due to flock by other process' do
    File.open("#{TEST_YAML_FILE}.lock", File::RDWR | File::CREAT, 0o0664) do |f|
      f.flock(File::LOCK_EX)

      expect { Timeout.timeout(0.001) { load_yaml_with_flock TEST_YAML_FILE } }.to raise_error(Timeout::Error)
    end
  end
end

describe 'save_yaml_with_flock' do
  let(:test_yaml_obj) { { 'key1' => 'value1', 'key2' => 'value2' } }

  after do
    FileUtils.rm_rf TEST_YAML_FILE
    FileUtils.rm_rf "#{TEST_YAML_FILE}.lock"
  end

  it 'saves yaml file' do
    save_yaml_with_flock test_yaml_obj, TEST_YAML_FILE
    yaml = load_yaml TEST_YAML_FILE
    expect(yaml['key2']).to eq 'value2'
  end

  it 'raises Timeout Error due to flock by other process' do
    File.open("#{TEST_YAML_FILE}.lock", File::RDWR | File::CREAT, 0o0664) do |f|
      f.flock(File::LOCK_EX)
      expect { Timeout.timeout(0.001) { save_yaml_with_flock test_yaml_obj, TEST_YAML_FILE } }.to raise_error(Timeout::Error)
    end
  end
end

describe 'yaml_merge_included_files' do
  yaml_merge_spec = <<EOF
contents: &borrow-1d
  #{YAML.load_file('jobs/borrow-1d.yaml').to_json}

:merge project path:
                        - <<: jobs/borrow-1d.yaml
                        - *borrow-1d
:merge relative path:
                        - <<: ../jobs/borrow-1d.yaml
                        - *borrow-1d
:merge absolute path:
                        - <<: #{LKP_SRC}/jobs/borrow-1d.yaml
                        - *borrow-1d
:merge into hash:
                        - a:
                          <<: jobs/borrow-1d.yaml
                        - a:
                          <<: *borrow-1d
:merge hash and update:
                        - a:
                          <<: jobs/borrow-1d.yaml
                          runtime: 1
                          b: c
                        - a:
                          <<: *borrow-1d
                          runtime: 1
                          b: c
:merge update hash:
                        - a:
                          b: c
                          runtime: 1
                          <<: jobs/borrow-1d.yaml
                        - a:
                          b: c
                          runtime: 1
                          <<: *borrow-1d
EOF

  yaml = yaml_merge_included_files(yaml_merge_spec, File.dirname(__FILE__))
  expects = YAML.unsafe_load(yaml)

  expects.each do |k, v|
    next unless k.instance_of?(Symbol)
    next unless v.instance_of?(Array) && v.size >= 2

    it k.to_s do
      expect(v[0]).to eq v[1]
    end
  end
end

describe 'yaml_merge_included_files with ignore' do
  let(:include_content) do
    <<~YAML
      key1: value1
      key2: value2
      key3: value3
      disk: some_disk
      d: some_d
      key_spaced : value_spaced
      nested_parent:
        nested_child: value_child
    YAML
  end
  let(:include_filename) { '/tmp/temp_include_ignore.yaml' }
  # Ensure clean absolute path for verify
  let(:absolute_path) { include_filename }

  before do
    File.write(include_filename, include_content)
  end

  after do
    FileUtils.rm_f(include_filename)
  end

  it 'ignores keys with unquoted filename' do
    yaml_input = "<<: #{absolute_path}, ignore: :key1"
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result).not_to have_key('key1')
    expect(result['key2']).to eq 'value2'
  end

  it 'overrides keys directly in include line' do
    yaml_input = "<<: '#{absolute_path}', ignore: :key1, key2: 'value_new'"
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result).not_to have_key('key1')
    expect(result['key2']).to eq 'value_new'
  end

  it 'overrides keys using unquoted filename syntax' do
    yaml_input = "<<: #{absolute_path}, key2: 'value_override'"
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result['key2']).to eq 'value_override'
  end

  it 'ignores a single key' do
    yaml_input = "<<: '#{absolute_path}', ignore: :key1"
    # Use dirname matching the file location or absolute path
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result).not_to have_key('key1')
    expect(result['key2']).to eq 'value2'
  end

  it 'ignores multiple keys' do
    yaml_input = "<<: '#{absolute_path}', ignore: [:key1, :key3]"
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result).not_to have_key('key1')
    expect(result).not_to have_key('key3')
    expect(result['key2']).to eq 'value2'
  end

  it 'does not ignore partial matches' do
    # Should ignore 'd' but keep 'disk'
    yaml_input = "<<: '#{absolute_path}', ignore: :d"
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result).not_to have_key('d')
    expect(result['disk']).to eq 'some_disk'
  end

  it 'supports IRB style array of ignore symbols' do
    yaml_input = "<<: '#{absolute_path}', ignore: [:key1, :key3]"
    merged_yaml = yaml_merge_included_files(yaml_input, File.dirname(absolute_path))
    result = YAML.unsafe_load(merged_yaml)

    expect(result).not_to have_key('key1')
    expect(result).not_to have_key('key3')
  end
end
