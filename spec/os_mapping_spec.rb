require 'spec_helper'

LKP_SRC_PATH = "#{LKP_SRC}/distro/adaptation".freeze

def find_duplicated_lines(default_mapping_path, os_specific_mapping_path)
  default_mapping_lines = read_mappings(default_mapping_path)
  os_specific_mapping_lines = read_mappings(os_specific_mapping_path)

  default_mapping_lines & os_specific_mapping_lines
end

def read_mappings(file_path)
  File.readlines(file_path).map(&:strip).reject(&:empty?)
end

def generate_mappings(lkp_src)
  files = Dir.entries(lkp_src).select do |f|
    file_path = File.join(lkp_src, f)
    File.file?(file_path) && !File.symlink?(file_path) && f != 'README.md'
  end

  mappings = Hash.new { |h, k| h[k] = [] }

  files.each do |file|
    base_name = file.split('-').first
    if file == base_name
      mappings[base_name].unshift(File.join(lkp_src, file))
    else
      mappings[base_name] << File.join(lkp_src, file)
    end
  end

  mappings
end

def find_common_packages(grouped_files)
  all_packages = grouped_files.values.flatten.map { |file| read_mappings(file) }.flatten.uniq
  common_packages = []

  all_packages.each do |package|
    common_packages << package if grouped_files.all? { |_, files| files.any? { |file| read_mappings(file).include?(package) } }
  end

  common_packages
end

describe 'package mapping uniqueness' do
  grouped_files = generate_mappings(LKP_SRC_PATH)

  grouped_files.each_value do |files|
    default_file = files.first
    os_specific_files = files[1..]

    os_specific_files.each do |os_specific_file|
      it "does not have duplicated lines between #{default_file} and #{os_specific_file}" do
        duplicated_lines = find_duplicated_lines(default_file, os_specific_file)
        expect(duplicated_lines).to be_empty, "Duplicated lines found between files:\nDefault: #{default_file}\nOS-specific: #{os_specific_file}\nDuplicated lines: #{duplicated_lines.join("\n")}"
      end
    end
  end

  it 'does not have any package mapping repeated in all groups' do
    common_packages = find_common_packages(grouped_files)
    expect(common_packages).to be_empty, "Common package mappings found in all groups: #{common_packages.join(', ')}"
  end
end
