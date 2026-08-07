require 'spec_helper'
require "#{LKP_SRC}/lib/job"
require "#{LKP_SRC}/lib/matrix"
require "#{LKP_SRC}/lib/stats"
require "#{LKP_SRC}/lib/yaml"

describe 'Matrix' do
  describe 'create_stats_matrix' do
    result_root = "#{LKP_SRC}/spec/fixtures/stats_part/result_root"
    sub_dirs = Dir.glob("#{result_root}/*")
    sub_dirs.each do |dir|
      next if dir =~ /.json/

      xit "invariance: #{dir}" do
        result_number = File.basename(dir)
        create_stats_matrix(dir)
        Dir.chdir(dir)
        system('gzip -d matrix.json.gz') if File.exist?('matrix.json.gz')
        new_stats_json =  JSON.parse_cached("#{dir}/stats.json")
        new_matrix_json = JSON.parse_cached("#{dir}/matrix.json")
        actual_stats_json = JSON.parse_cached("#{result_root}/stats_#{result_number}.json")
        actual_matrix_json = JSON.parse_cached("#{result_root}/matrix_#{result_number}.json")

        expect(new_stats_json).to eq actual_stats_json
        expect(new_matrix_json).to eq actual_matrix_json
      end
    end
  end
end
