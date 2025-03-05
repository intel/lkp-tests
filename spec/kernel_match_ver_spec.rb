require 'spec_helper'
require "#{LKP_SRC}/lib/kernel_tag"

describe '#kernel_match_version?' do
  it 'returns true for a match with == operator' do
    kernel_version = 'v5.10'
    expected_versions = ['== v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(true)
  end

  it 'returns false when kernel version is not equal to the expected version' do
    kernel_version = 'v5.10'
    expected_versions = ['== v5.9']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'returns false when using <= operator and kernel version is equal to the expected version due to workaround in the code' do
    kernel_version = 'v5.10'
    expected_versions = ['<= v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'returns false when using <= operator but kernel version is greater than the expected version' do
    kernel_version = 'v5.11'
    expected_versions = ['<= v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'returns true when using < operator and kernel version is lesser than the expected version' do
    kernel_version = 'v6.2'
    expected_versions = ['v4.15-rc1', '< v6.5']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(true)
  end

  it 'returns true when using >= operator and kernel version is greater than or equal to the expected version' do
    kernel_version = 'v5.10'
    expected_versions = ['>= v5.9']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(true)
  end

  it 'returns false when using >= operator but kernel version is less than the expected version' do
    kernel_version = 'v5.8'
    expected_versions = ['>= v5.9']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'returns true when using > operator and kernel version is greater than the expected version' do
    kernel_version = 'v5.11'
    expected_versions = ['> v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(true)
  end

  it 'returns false when using > operator but kernel version is less than the expected version' do
    kernel_version = 'v5.9'
    expected_versions = ['> v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'handles -rc versions correctly' do
    kernel_version = 'v5.7-rc3'
    expected_versions = ['== v5.7']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'handles prerelease versions correctly with the default operator' do
    kernel_version = 'v5.7-rc1'
    expected_versions = ['>= v5.7-rc2']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  # Example given
  it 'returns true for kernel_match_version?(v5.9, [v4.15-rc1, < v5.10])' do
    kernel_version = 'v5.9'
    expected_versions = ['v4.15-rc1', '< v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(true)
  end

  it 'returns false for kernel_match_version?(v5.10, [v4.15-rc1, < v5.10])' do
    kernel_version = 'v5.10'
    expected_versions = ['v4.15-rc1', '< v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'returns false for kernel_match_version?(v4.15, [>= v4.15-rc1, < v5.10])' do
    kernel_version = 'v4.15'
    expected_versions = ['>= v4.15-rc1', 'v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end

  it 'returns false for kernel_match_version?(v5.10, [v4.15-rc1, <= v5.10])' do
    kernel_version = 'v5.10'
    expected_versions = ['v4.15-rc1', '<= v5.10']
    expect(kernel_match_version?(kernel_version, expected_versions)).to eq(false)
  end
end
