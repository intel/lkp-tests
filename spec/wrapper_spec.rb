require 'spec_helper'
require "#{LKP_SRC}/lib/job"

describe Job do
  let(:job) { described_class.new }

  include_context 'mocked filesystem'

  before do
    allow(job).to receive(:lkp_src).and_return(tmp_lkp_src)
    # Be smarter to check file existence
    File.write("#{tmp_lkp_src}/bin/program-options", <<~SCRIPT)
      #!/bin/sh
      if [ ! -f "$1" ]; then
        echo "File not found: $1" >&2
        exit 1
      fi
    SCRIPT
    FileUtils.chmod(0o755, "#{tmp_lkp_src}/bin/program-options")
  end

  describe '#init_program_options' do
    it 'loads wrapper and dwrapper from correct paths' do
      # This triggers init_program_options
      expect { job.send(:init_program_options) }.not_to raise_error

      expect(job.referenced_programs).to include('wrapper')
      expect(job.referenced_programs).to include('dwrapper')
    end
  end
end
