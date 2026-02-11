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
      'setup/wrapper',
      'daemon/wrapper',
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
  end

  after do
    FileUtils.remove_entry tmp_lkp_src
    $programs_cache = nil
  end
end
