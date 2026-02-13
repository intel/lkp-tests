require 'tmpdir'
require 'fileutils'

shared_context 'mocked filesystem' do
  let(:tmp_lkp_src) { Dir.mktmpdir }

  before do
    # Create executables
    [
      'bin/program-options',
      'bin/run-test',
      'stats/wrapper',
      'bin/run-setup',
      'bin/run-daemon',
      'programs/mysetup/setup',
      'programs/mysetup2/setup',
      'programs/mysetup2/parse',
      'programs/mydaemon/daemon',
      'programs/myprog/run',
      'programs/myprog/parse'
    ].each do |f|
      path = "#{tmp_lkp_src}/#{f}"
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
      FileUtils.chmod(0o755, path)
    end

    # Create mock category file
    FileUtils.mkdir_p("#{tmp_lkp_src}/include/category")
    File.write("#{tmp_lkp_src}/include/category/mock-category", <<~YAML)
      kmsg:
      heartbeat:
      meminfo:
    YAML

    # Create other directories
    FileUtils.mkdir_p("#{tmp_lkp_src}/programs/mock_setup")
    FileUtils.mkdir_p("#{tmp_lkp_src}/programs/program_setup")

    # Create directory-based includes
    FileUtils.mkdir_p("#{tmp_lkp_src}/programs/myfs/include")
    FileUtils.touch("#{tmp_lkp_src}/programs/myfs/include/subconf1")

    # Create directory-based includes with symlink to parent
    FileUtils.mkdir_p("#{tmp_lkp_src}/programs/myfs_link")
    File.symlink("#{tmp_lkp_src}/programs/myfs", "#{tmp_lkp_src}/programs/myfs_link/symlink")
    # Actually create a symlink for the whole program directory
    File.symlink('myfs', "#{tmp_lkp_src}/programs/myfs_symlink")

    # Create file-based includes
    FileUtils.mkdir_p("#{tmp_lkp_src}/programs/mytask")
    FileUtils.touch("#{tmp_lkp_src}/programs/mytask/include")
  end

  after do
    FileUtils.remove_entry tmp_lkp_src
    $programs_cache = nil
  end
end
