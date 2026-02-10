require 'spec_helper'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/string"

def sorted_file_content(file_path)
  # remove empty line and line starting with #
  Bash.run("LC_ALL=C sort -f #{file_path} | grep -hv '^\\s*#\\|^\\s*$' | uniq")
end

def with_shebang?(file)
  File.open(file, 'r') do |f|
    return f.readline.start_with?('#!')
  end
rescue EOFError
  false
end

def filtered_files(path, filter)
  Dir.glob("#{path}/**/*")
     .select { |f| File.file?(f) }
     .reject { |f| f =~ /\.(sh|rb|yml|py|txt)$/ || File.symlink?(f) || with_shebang?(f) }
     .select { |f| filter.nil? || filter.call(File.basename(f)) }
end

describe 'Directory File Sorting' do
  directories = {
    'adaptation' => {
      path: "#{LKP_SRC}/distro/adaptation",
      filter: ->(filename) { filename != 'README.md' }
    },

    'adaptation_pkg' => {
      path: "#{LKP_SRC}/distro/adaptation-pkg"
    },

    'programs' => {
      path: "#{LKP_SRC}/programs",
      filter: ->(filename) { filename.start_with?('depends') }
    },

    'etc' => {
      path: "#{LKP_SRC}/etc",
      filter: ->(filename) { filename != 'makepkg.conf' }
    }
  }

  directories.each do |dir_name, config|
    context "in #{dir_name}" do
      filtered_files(config[:path], config[:filter]).each do |file|
        it "#{file} has sorted content and no duplicates" do
          actual = File.readlines(file)
                       .reject { |line| line.blank? || line.start_with?('#') }
                       .join

          expect(actual.chomp).to eq(sorted_file_content(file))
        end
      end
    end
  end
end
