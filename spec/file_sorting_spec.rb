require 'spec_helper'

describe 'Directory File Sorting' do
  def sorted_file_content(file_path)
    `sort -f #{file_path}`.split("\n")
  end

  def filtered_files(path, filter)
    Dir.entries(path)
       .reject { |f| File.directory?(File.join(path, f)) || f.start_with?('.') }
       .select { |f| filter.nil? || filter.call(f) }
  end

  directories = {
    'adaptation' => {
      path: "#{LKP_SRC}/distro/adaptation",
      filter: ->(filename) { filename != 'README.md' }
    },
    'adaptation_pkg' => {
      path: "#{LKP_SRC}/distro/adaptation-pkg",
      filter: nil
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

  describe 'File Sorting Tests' do
    directories.each do |dir_name, config|
      context "in #{dir_name}" do
        let(:files) { filtered_files(config[:path], config[:filter]) }

        it 'has sorted content and no duplicates in each file' do
          files.each do |filename|
            file_path = File.join(config[:path], filename)
            next if File.directory?(file_path)

            content = File.readlines(file_path, chomp: true)
            sorted_and_unique_content = sorted_file_content(file_path).uniq

            expect(content).to eq(sorted_and_unique_content),
                               "Content in #{file_path} is not sorted or unique."
          end
        end
      end
    end
  end
end
