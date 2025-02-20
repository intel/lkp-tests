require 'spec_helper'
require 'timeout'
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/ruby"

TEST_YAML_FILE = '/tmp/test.yaml'.freeze

describe 'load_yaml_with_flock' do
  before(:example) do
    File.open(TEST_YAML_FILE, 'w') do |f|
      f.write("key1: value1\nkey2: value2\n")
    end
  end

  it 'returns correct value' do
    yaml = load_yaml_with_flock TEST_YAML_FILE
    expect(yaml['key2']).to eq 'value2'
  end

  it 'raises Timeout Error due to flock by other process' do
    f = File.open("#{TEST_YAML_FILE}.lock", File::RDWR | File::CREAT, 0o0664)
    f.flock(File::LOCK_EX)

    expect { Timeout.timeout(0.001) { load_yaml_with_flock TEST_YAML_FILE } }.to raise_error(Timeout::Error)
    f.close
  end

  after(:example) do
    FileUtils.rm TEST_YAML_FILE
    FileUtils.rm "#{TEST_YAML_FILE}.lock"
  end
end

describe 'save_yaml_with_flock' do
  let(:test_yaml_obj) { { 'key1' => 'value1', 'key2' => 'value2' } }

  it 'saves yaml file' do
    save_yaml_with_flock test_yaml_obj, TEST_YAML_FILE
    yaml = load_yaml TEST_YAML_FILE
    expect(yaml['key2']).to eq 'value2'
  end

  it 'raises Timeout Error due to flock by other process' do
    f = File.open("#{TEST_YAML_FILE}.lock", File::RDWR | File::CREAT, 0o0664)
    f.flock(File::LOCK_EX)
    expect { Timeout.timeout(0.001) { save_yaml_with_flock test_yaml_obj, TEST_YAML_FILE } }.to raise_error(Timeout::Error)
    f.close
  end

  after(:example) do
    FileUtils.rm_rf TEST_YAML_FILE
    FileUtils.rm_rf "#{TEST_YAML_FILE}.lock"
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
