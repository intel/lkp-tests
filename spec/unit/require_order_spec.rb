require 'spec_helper'

describe 'require order' do
  # A file opts out of the alphabetical check by including a
  # 'require-order-exempt:' comment explaining why (e.g. a load-time
  # dependency between two of its own requires) -- keeps the reason
  # colocated with the file it applies to, instead of hardcoded here.
  files = Dir.glob("#{LKP_SRC}/**/*.rb").reject { |f| f.include?('/vendor/') || f.include?('/web/backend/spec/') || f.end_with?('lib/time.rb') || File.read(f) =~ /^# require-order-exempt:/ } +
          Dir.glob("#{LKP_SRC}/{bin,sbin,tools,programs,filters,lkp-exec}/*").select { |f| File.file?(f) && File.read(f, 100) =~ /ruby/ }

  files.each do |file_path|
    describe file_path do
      let(:content) { File.read(file_path) }
      let(:lines) { content.lines }

      it 'has sorted require statements' do
        require_lines = lines.grep(/^require /)

        sorted_lines = require_lines.sort_by do |line|
          if line.include?('LKP_SRC')
            [1, line]
          elsif line.include?('LKP_CORE_SRC')
            [2, line]
          elsif line =~ /#\{[A-Z_]+\}/
            # any other interpolated all-caps root constant (e.g. a
            # suite-local *_ROOT) sorts after LKP_SRC/LKP_CORE_SRC too
            [3, line]
          else
            [0, line]
          end
        end

        expect(require_lines).to eq(sorted_lines)
      end

      it 'does not have empty lines between require statements' do
        first_require_index = lines.index { |l| l =~ /^require / }
        last_require_index = lines.rindex { |l| l =~ /^require / }

        if first_require_index && last_require_index
          require_block = lines[first_require_index..last_require_index]
          expect(require_block.grep(/^\s*$/)).to be_empty
        end
      end
    end
  end
end
