require 'spec_helper'

describe 'require order' do
  files = Dir.glob("#{LKP_SRC}/**/*.rb").reject { |f| path_excluded?(f) } +
          Dir.glob("#{LKP_SRC}/{bin,sbin,tools,programs,filters,lkp-exec}/*").select { |f| File.file?(f) && File.read(f, 100) =~ /ruby/ }

  files.each do |file_path|
    describe file_path do
      let(:content) { File.read(file_path) }
      let(:lines) { content.lines }

      it 'has sorted require statements' do
        require_lines = lines.grep(/^require /)

        # spec_helper always sorts first among plain requires, ahead of
        # plain alphabetical order: a bare require that runs before
        # spec_helper's $LOAD_PATH cleanup can silently resolve to this
        # repo's own same-named lib/*.rb wrapper instead of the intended
        # stdlib/gem.
        sorted_lines = require_lines.sort_by do |line|
          if line.include?('LKP_SRC')
            [1, line]
          elsif line.include?('LKP_CORE_SRC')
            [2, line]
          elsif line =~ /#\{[A-Z_]+\}/
            # any other interpolated all-caps root constant (e.g. a
            # suite-local *_ROOT) sorts after LKP_SRC/LKP_CORE_SRC too
            [3, line]
          elsif line == "require 'spec_helper'\n"
            [0, '']
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
