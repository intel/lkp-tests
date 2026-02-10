require 'spec_helper'
require 'tempfile'
require "#{LKP_SRC}/lib/bash"

describe 'yaml-to-shell-vars' do
  let(:script) { "#{LKP_SRC}/bin/yaml-to-shell-vars" }
  let(:yaml_file) { Tempfile.new(['test', '.yaml']) }

  after do
    yaml_file.close
    yaml_file.unlink
  end

  def run_script(args = '')
    Bash.run("#{script} #{args} #{yaml_file.path}")
  end

  it 'converts simple key-value pairs' do
    File.write(yaml_file.path, <<~YAML)
      key1: value1
      key2: value2
    YAML

    output = run_script
    expect(output).to include('key1=value1')
    expect(output).to include('key2=value2')
  end

  it 'sanitizes variable names' do
    File.write(yaml_file.path, <<~YAML)
      foo-bar: val1
      123var: val2
      foo.bar: val3
    YAML

    output = run_script
    expect(output).to include('foo_bar=val1')
    expect(output).to include('_23var=val2')
    expect(output).to include('foo_bar=val3')
  end

  it 'escapes special characters in values' do
    File.write(yaml_file.path, <<~YAML)
      key1: "value with spaces"
      key2: "value'with'quotes"
      key3: "value;with;semicolons"
    YAML

    output = run_script
    expect(output).to include('key1=value\\ with\\ spaces')
    expect(output).to include("key2=value\\'with\\'quotes")
    expect(output).to include('key3=value\\;with\\;semicolons')
  end

  it 'supports --prefix option' do
    File.write(yaml_file.path, 'key: value')
    output = run_script('--prefix MY_')
    expect(output).to include('MY_key=value')
  end

  it 'supports --array option for associative arrays' do
    File.write(yaml_file.path, 'key: value')
    output = run_script('--array my_arr')
    expect(output).to include('my_arr[key]=value')
  end

  it 'combines --prefix and --array options' do
    File.write(yaml_file.path, 'key: value')
    output = run_script('--prefix PRE_ --array my_arr')
    expect(output).to include('my_arr[PRE_key]=value')
  end

  context 'with --expand option' do
    it 'quotes values containing $' do
      File.write(yaml_file.path, 'key: $VAR')
      output = run_script('--expand')
      expect(output).to include('key="$VAR"')
    end

    it 'does not quote values without $' do
      File.write(yaml_file.path, 'key: value')
      output = run_script('--expand')
      expect(output).to include('key=value')
    end
  end

  describe 'complex value handling' do
    it 'handles array values by joining with newline' do
      File.write(yaml_file.path, <<~YAML)
        items:
          - item1
          - item2
      YAML
      output = run_script
      expect(output).to include('items=')
      expect(output).to include('item1')
      expect(output).to include('item2')
    end

    it 'handles hash values by taking the first key' do
      File.write(yaml_file.path, <<~YAML)
        config:
          k1: v1
      YAML
      output = run_script
      expect(output).to include('config=k1')
    end

    it 'handles array of hashes' do
      File.write(yaml_file.path, <<~YAML)
         list:
           - k1: v1
           - k2: v2
      YAML
      output = run_script
      expect(output).to include('list=')
      expect(output).to include('k1')
      expect(output).to include('k2')
    end
  end
end
