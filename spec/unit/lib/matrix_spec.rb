require 'spec_helper'
require "#{LKP_SRC}/lib/lkp_tmpdir"
require "#{LKP_SRC}/lib/matrix"
require "#{LKP_SRC}/lib/yaml"

describe 'Matrix' do
  before(:all) do
    @tmp_dir = LKP::TmpDir.new('matrix-spec-')
  end

  after(:all) do
    @tmp_dir.clean!
  end

  describe 'remove_rt_from_matrix' do
    it 'deletes only the named rt column and its stats_source entry' do
      matrix_root = @tmp_dir.path('commit')
      FileUtils.mkdir_p matrix_root

      matrix = {
        'stats_source' => %w[/result/.../0/stats.json /result/.../1/stats.json],
        'last_state.booting' => [1, 0],
        'last_state.is_incomplete_run' => [1, 0],
        'uptime.boot' => [10, 20]
      }
      save_json(matrix, "#{matrix_root}/matrix.json")

      remove_rt_from_matrix('/result/.../0', matrix_root)

      new_matrix = JSON.parse_cached("#{matrix_root}/matrix.json")
      expect(new_matrix['stats_source']).to eq ['/result/.../1/stats.json']
      expect(new_matrix['uptime.boot']).to eq [20]
      expect(new_matrix).not_to have_key 'last_state.booting'
      expect(new_matrix).not_to have_key 'last_state.is_incomplete_run'
    end

    it 'does nothing when the rt is not present in matrix.json' do
      matrix_root = @tmp_dir.path('commit-no-match')
      FileUtils.mkdir_p matrix_root

      matrix = {
        'stats_source' => ['/result/.../1/stats.json'],
        'uptime.boot' => [20]
      }
      save_json(matrix, "#{matrix_root}/matrix.json")

      remove_rt_from_matrix('/result/.../0', matrix_root)

      expect(JSON.parse_cached("#{matrix_root}/matrix.json")).to eq matrix
    end

    it 'does nothing when matrix.json does not exist' do
      matrix_root = @tmp_dir.path('commit-missing')
      FileUtils.mkdir_p matrix_root

      expect { remove_rt_from_matrix('/result/.../0', matrix_root) }.not_to raise_error
      expect(File.exist?("#{matrix_root}/matrix.json")).to be false
    end
  end

  describe 'unite_remove_empty_stats' do
    it 'removes a key whose values are all-zero Integer padding after reprocess' do
      matrix = {
        'dmesg.timestamp:WARNING:possible_circular_locking_dependency_detected' => [0] * 14,
        'uptime.boot' => [10, 20]
      }

      result = unite_remove_empty_stats(matrix)

      expect(result).not_to have_key 'dmesg.timestamp:WARNING:possible_circular_locking_dependency_detected'
      expect(result['uptime.boot']).to eq [10, 20]
    end

    it 'removes a key with a literally empty array' do
      matrix = { 'empty.stat' => [], 'uptime.boot' => [10] }

      result = unite_remove_empty_stats(matrix)

      expect(result).not_to have_key 'empty.stat'
    end

    it 'keeps a key with a genuine non-zero Integer value mixed with zeros' do
      matrix = { 'dmesg.boot_failures' => [0, 0, 1, 0] }

      result = unite_remove_empty_stats(matrix)

      expect(result).to have_key 'dmesg.boot_failures'
    end

    it 'keeps a key whose all-zero values are Float, not Integer' do
      matrix = { 'perf-stat.overall.path-length' => [0.0, 0.0] }

      result = unite_remove_empty_stats(matrix)

      expect(result).to have_key 'perf-stat.overall.path-length'
    end
  end
end
