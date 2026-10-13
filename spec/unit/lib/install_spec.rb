require 'spec_helper'
require 'tempfile'
require "#{LKP_SRC}/lib/bash"

describe 'adapt_package' do
  def run_adapt_package(pkg_name, distro_file)
    Bash.run(". #{LKP_SRC}/lib/install.sh && adapt_package #{pkg_name} #{distro_file}",
             returns: [0, 1])
  end

  # Regression for a bare key being swallowed by a longer, arch-qualified
  # sibling key that shares it as a literal prefix (e.g. "libc6-dev" vs
  # "libc6-dev:i386"). `grep "^$pkg_name:"` alone cannot tell the two
  # apart since both lines literally start with "libc6-dev:".
  it 'does not match a bare key against a longer arch-qualified sibling key' do
    Tempfile.create('adaptation') do |f|
      f.puts 'libc6-dev:i386:'
      f.flush

      expect(run_adapt_package('libc6-dev', f.path)).to be_empty
    end
  end

  it 'matches the bare key itself when present' do
    Tempfile.create('adaptation') do |f|
      f.puts 'libc6-dev: glibc-devel glibc-static'
      f.puts 'libc6-dev:i386: glibc-devel.i686 glibc-static.i686'
      f.flush

      expect(run_adapt_package('libc6-dev', f.path)).to eq('libc6-dev: glibc-devel glibc-static')
    end
  end

  it 'still matches the arch-qualified key itself' do
    Tempfile.create('adaptation') do |f|
      f.puts 'libc6-dev:i386:'
      f.flush

      expect(run_adapt_package('libc6-dev:i386', f.path)).to eq('libc6-dev:i386:')
    end
  end

  # '+' is a quantifier in an extended regex, so an ERE-based anchor would
  # silently stop matching names such as "g++" and "libstdc++-dev".
  it 'matches a key containing literal + characters' do
    Tempfile.create('adaptation') do |f|
      f.puts 'g++: gcc-c++'
      f.puts 'g++-multilib:'
      f.puts 'libstdc++-dev: libstdc++-devel libstdc++-static'
      f.flush

      expect(run_adapt_package('g++', f.path)).to eq('g++: gcc-c++')
      expect(run_adapt_package('g++-multilib', f.path)).to eq('g++-multilib:')
      expect(run_adapt_package('libstdc++-dev', f.path)).to eq('libstdc++-dev: libstdc++-devel libstdc++-static')
    end
  end

  it 'does not let a + key match a different key through quantifier semantics' do
    Tempfile.create('adaptation') do |f|
      f.puts 'g:'
      f.puts 'gg: other'
      f.flush

      expect(run_adapt_package('g++', f.path)).to be_empty
    end
  end

  it 'matches a key with an empty value' do
    Tempfile.create('adaptation') do |f|
      f.puts 'libbz2-1.0:'
      f.puts 'libbz2-1.0-dev: libbz2-devel'
      f.flush

      expect(run_adapt_package('libbz2-1.0', f.path)).to eq('libbz2-1.0:')
    end
  end

  it 'does not match a key that merely shares a prefix with the requested name' do
    Tempfile.create('adaptation') do |f|
      f.puts 'libusb-1.0-0-dev: libusb-devel'
      f.flush

      expect(run_adapt_package('libusb-1.0-0', f.path)).to be_empty
    end
  end

  it 'prefers the bare key and returns only it when the arch-qualified key comes first' do
    Tempfile.create('adaptation') do |f|
      f.puts 'libc6-dev:i386: glibc-devel.i686'
      f.puts 'libc6-dev: glibc-devel'
      f.flush

      expect(run_adapt_package('libc6-dev', f.path)).to eq('libc6-dev: glibc-devel')
    end
  end

  it 'returns failure when the mapping file is missing or not given' do
    expect(Bash.run(". #{LKP_SRC}/lib/install.sh && adapt_package g++ /nonexistent", returns: [0, 1])).to be_empty
    expect(Bash.run(". #{LKP_SRC}/lib/install.sh && adapt_package g++", returns: [0, 1])).to be_empty
  end
end
