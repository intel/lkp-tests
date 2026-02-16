require 'spec_helper'
require "#{LKP_SRC}/lib/bash"
require "#{LKP_SRC}/lib/programs"
require_relative '../lib/stats'

describe 'stats' do
  describe 'scripts' do
    yaml_files = Dir.glob ["#{LKP_SRC}/spec/stats/*/*.yaml"]
    yaml_files.each do |yaml_file|
      file = yaml_file.chomp '.yaml'
      it "invariance: #{file}" do
        script = File.basename(File.dirname(file))
        old_stat = File.read yaml_file

        stat_script = LKP::Programs.find_parser(script)
        new_stat = case script
                   when /^(kmsg)$/
                     Bash.run("RESULT_ROOT=/boot/1/vm- #{stat_script} #{file}")
                   when /^(dmesg|mpstat|fio)$/
                     Bash.run("#{stat_script} #{file}")
                   else
                     Bash.run("#{stat_script} < #{file}")
                   end
        raise "stats script exitstatus #{$CHILD_STATUS.exitstatus}" unless $CHILD_STATUS.success?

        expect(new_stat).to eq old_stat.chomp
      end
    end
  end

  describe 'kpi_stat_direction' do
    it 'matches the correct value' do
      change_percentage = 1
      a = 'aim9.add_float.ops_per_sec'
      b = 'pts.aobench.0.seconds'
      c = 'aim9.test'

      expect(kpi_stat_direction(a, change_percentage)).to eq 'improvement'
      expect(kpi_stat_direction(b, change_percentage)).to eq 'regression'
      expect(kpi_stat_direction(c, change_percentage)).to eq 'undefined'
    end
  end

  describe 'Stats Generation' do
    def build_stat_compare(k: 'stat', a: nil, b: {}, is_incomplete_run: false, options: {}, is_force_stat: false)
      a ||= { k => [] }
      options = options.merge("force_#{k}" => true) if is_force_stat
      StatCompare.new(k, a, b, is_incomplete_run, options)
    end

    describe '#__get_changed_stats' do
      let(:matrix_a) { { 'cpu.usage' => [10, 10, 10] } }
      let(:matrix_b) { { 'cpu.usage' => [20, 20, 20] } }
      let(:is_incomplete_run) { false }
      let(:options) { {} }

      context 'when stats are identical' do
        let(:matrix_b) { { 'cpu.usage' => [10, 10, 10] } }

        it 'returns empty hash' do
          options['more'] = true

          result = __get_changed_stats(matrix_a, matrix_b, is_incomplete_run, options)
          expect(result).to be_empty
        end
      end

      context 'with options[perf]' do
        before do
          options['perf'] = true
          options['more'] = true
        end

        it 'skips if not a perf metric' do
          matrix_a = { 'unknown.stat' => [10] }
          matrix_b = { 'unknown.stat' => [20] }

          result = __get_changed_stats(matrix_a, matrix_b, is_incomplete_run, options)
          expect(result).to be_empty
        end

        it 'includes if it is a perf metric' do
          matrix_a = { 'vmstat.cpu.us' => [10, 10, 10] }
          matrix_b = { 'vmstat.cpu.us' => [20, 20, 20] }

          result = __get_changed_stats(matrix_a, matrix_b, is_incomplete_run, options)
          expect(result).to have_key('vmstat.cpu.us')
        end
      end

      context 'with yaml test cases' do
        Dir.glob("#{File.dirname(__FILE__)}/stats_changed_stats/*.yaml").each do |yaml_file|
          it "verifies #{File.basename(yaml_file)}" do
            test_case = YAML.load_file(yaml_file)
            matrix_a = test_case['matrix_a']
            matrix_b = test_case['matrix_b']
            options = test_case['options'] || {}
            expected = test_case['expected']

            result = __get_changed_stats(matrix_a, matrix_b, is_incomplete_run, options)

            if expected.nil? || expected.empty?
              expect(result).to be_empty.or be_nil
            else
              expect(result.keys).to match_array(expected.keys)
              expected.each do |stat_key, expected_values|
                actual = result[stat_key].dup
                actual.delete('ttl')

                expect(actual.keys).to match_array(expected_values.keys)

                expected_values.each do |k, val|
                  if %w[mean_a mean_b].include?(k)
                    expect(actual[k]).to eq(val)
                  elsif val.is_a?(Float)
                    expect(actual[k]).to be_within(0.05).of(val)
                  else # rubocop:disable Lint/DuplicateBranch
                    expect(actual[k]).to eq(val)
                  end
                end
              end
            end
          end
        end
      end
    end

    describe '.calc_stats_metrics' do
      it 'calculates metrics correctly' do
        # A: [10, 15, 20, 25, 30] -> min: 10, mean: 20, max: 30, len: 20, size: 5
        # B: [15, 20, 25, 30, 35] -> min: 15, mean: 25, max: 35, len: 20, size: 5
        summary_a = StatSummary.new([10, 15, 20, 25, 30])
        summary_b = StatSummary.new([15, 20, 25, 30, 35])

        result = StatCompare.calc_stats_metrics(summary_a, summary_b)
        expect(result).to eq([35, 20, 0, 20, 5, 25.0 / 20.0])
      end

      context 'when sorted_a size is small' do
        it 'adjusts x if x < z' do
          # a len: 20, size: 2. z len: 45
          summary_a = StatSummary.new([10, 30])
          summary_b = StatSummary.new([15, 60])

          # x = 30-10=20. x(20) < z(45). size_a(2) <= 2. So x should become z (45)
          result = StatCompare.calc_stats_metrics(summary_a, summary_b)
          x = result[1]
          z = result[3]
          expect(x).to eq(z)
        end
      end
    end

    describe '#skip_function_stat?' do
      subject { stat_compare.send(:skip_function_stat?) }

      context 'when is_force_stat is true' do
        let(:stat_compare) { build_stat_compare(k: 'test.fail', is_force_stat: true) }

        it { is_expected.to be_falsey }
      end

      context 'when k is a kernel message stat' do
        let(:stat_compare) { build_stat_compare(k: 'dmesg.foo') }

        it { is_expected.to be_falsey }
      end

      context 'when k is a fail stat' do
        context 'and b has no pass stat' do
          let(:stat_compare) { build_stat_compare(k: 'test.fail', b: {}) }

          it { is_expected.to be_truthy }
        end

        context 'and b has pass stat' do
          let(:stat_compare) { build_stat_compare(k: 'test.fail', b: { 'test.pass' => [] }) }

          it { is_expected.to be_falsey }
        end
      end

      context 'when k is a pass stat' do
        context 'and b has no fail stat' do
          let(:stat_compare) { build_stat_compare(k: 'test.pass', b: {}) }

          it { is_expected.to be_truthy }
        end

        context 'and b has fail stat' do
          let(:stat_compare) { build_stat_compare(k: 'test.pass', b: { 'test.fail' => [] }) }

          it { is_expected.to be_falsey }
        end
      end
    end

    describe '#skip_regular_stat?' do
      subject { stat_compare.send(:skip_regular_stat?) }

      let(:large_a) { { 'cpu.usage' => Array.new(10, 1) } }
      let(:large_b) { { 'cpu.usage' => Array.new(10, 1) } }

      context 'when using defaults (large cols)' do
        let(:stat_compare) { build_stat_compare(k: 'cpu.usage', a: large_a, b: large_b) }

        it { is_expected.to be_falsey }
      end

      context 'when is_force_stat is true' do
        let(:stat_compare) { build_stat_compare(k: 'cpu.usage', a: large_a, b: large_b, is_force_stat: true) }

        it { is_expected.to be_falsey }
      end

      context 'when cols are small' do
        let(:small_a) { { 'cpu.usage' => Array.new(2, 1) } }
        let(:small_b) { { 'cpu.usage' => Array.new(2, 1) } }
        let(:stat_compare) { build_stat_compare(k: 'cpu.usage', a: small_a, b: small_b) }

        it { is_expected.to be_truthy }

        context 'and options[whole] is true' do
          let(:stat_compare) { build_stat_compare(k: 'cpu.usage', a: small_a, b: small_b, options: { 'whole' => true }) }

          it { is_expected.to be_falsey }
        end
      end

      context 'when tbox_group is vh-' do
        let(:stat_compare) { build_stat_compare(k: 'cpu.usage', a: large_a, b: large_b, options: { 'tbox_group' => 'vh-test' }) }

        it { is_expected.to be_truthy }
      end

      context 'when tbox_group is vm-' do
        context 'and memory change' do
          let(:stat_compare) do
            k = 'meminfo.MemTotal'
            build_stat_compare(
              k: k,
              a: { k => Array.new(10, 1) },
              b: { k => Array.new(10, 1) },
              options: { 'tbox_group' => 'vm-test' }
            )
          end

          it { is_expected.to be_truthy }

          context 'and is_perf_test_vm' do
            let(:stat_compare) do
              k = 'meminfo.MemTotal'
              build_stat_compare(
                k: k,
                a: { k => Array.new(10, 1) },
                b: { k => Array.new(10, 1) },
                options: { 'tbox_group' => 'vm-test', 'is_perf_test_vm' => true }
              )
            end

            it { is_expected.to be_falsey }
          end
        end

        context 'and no memory change' do
          let(:stat_compare) { build_stat_compare(k: 'cpu.usage', a: large_a, b: large_b, options: { 'tbox_group' => 'vm-test' }) }

          it { is_expected.to be_falsey }
        end
      end
    end

    describe '#skip_small_change?' do
      subject { stat_compare.send(:skip_small_change?, ratio, delta, max) }

      let(:ratio) { 1.1 }
      let(:delta) { 10 }
      let(:max) { 100 }
      let(:stat_compare) { build_stat_compare(k: 'vmstat.cpu.us') }

      context 'when is_force_stat is true' do
        let(:stat_compare) { build_stat_compare(k: 'vmstat.cpu.us', is_force_stat: true) }

        it { is_expected.to be_falsey }
      end

      context 'when perf-profile stat' do
        let(:stat_compare) { build_stat_compare(k: 'perf-profile.cycles', options: { 'perf-profile' => true }) }

        it { is_expected.to be_falsey }
      end

      context 'when ratio <= 1.01' do
        let(:ratio) { 1.01 }

        it { is_expected.to be_truthy }
      end

      context 'when ratio <= 1.05' do
        let(:ratio) { 1.04 }

        context 'and not perf_metric' do
          let(:stat_compare) { build_stat_compare(k: 'unknown.stat') }

          it { is_expected.to be_truthy }
        end

        context 'and is perf_metric' do
          let(:stat_compare) { build_stat_compare(k: 'vmstat.cpu.us') }

          it { is_expected.to be_falsey }
        end
      end

      context 'when not reasonable_perf_change' do
        let(:stat_compare) { build_stat_compare(k: 'iostat.test') }
        let(:max) { 1 }

        it { is_expected.to be_truthy }
      end

      context 'when all conditions met' do
        it { is_expected.to be_falsey }
      end
    end

    describe '.format_interval' do
      it 'formats the interval correctly' do
        summary_a = StatSummary.new([1.5, 2.5])
        summary_b = StatSummary.new([3.5, 4.5])

        expect(StatCompare.format_interval(summary_a, summary_b)).to eq('[ 1.5        - 2.5        ] -- [ 3.5        - 4.5        ]')
      end
    end

    describe '#skip_stat?' do
      subject { stat_compare.send(:skip_stat?) }

      let(:stat_compare) { build_stat_compare(k: 'stat.key', a: { 'stat.key' => [1, 2, 3] }) }

      context 'when values contain string' do
        let(:stat_compare) { build_stat_compare(k: 'stat.key', a: { 'stat.key' => [1, 'string'] }) }

        it { is_expected.to be_truthy }
      end

      context 'when perf option set and not perf metric' do
        let(:stat_compare) { build_stat_compare(k: 'unknown.stat', options: { 'perf' => true }) }

        it { is_expected.to be_truthy }
      end

      context 'when is_incomplete_run' do
        context 'and k is not allowed' do
          let(:stat_compare) { build_stat_compare(k: 'cpu.usage', is_incomplete_run: true) }

          it { is_expected.to be_truthy }
        end

        context 'and k is allowed' do
          let(:stat_compare) { build_stat_compare(k: 'dmesg.boot', is_incomplete_run: true) }

          it { is_expected.to be_falsey }
        end
      end

      context 'when not more options' do
        let(:no_more_opt) { { 'more' => false } }

        context 'and stat is in Denylist and not in ReportAllowlist' do
          let(:stat_compare) { build_stat_compare(k: 'Modules_linked_in', options: no_more_opt) }

          it { is_expected.to be_truthy }
        end

        context 'and stat is in ReportAllowlist' do
          let(:stat_compare) { build_stat_compare(k: 'proc-vmstat.nr_active', a: { 'proc-vmstat.nr_active' => [1, 2, 3] }, options: no_more_opt) }

          it { is_expected.to be_falsey }
        end

        context 'and stat is bisectable (not denied)' do
          let(:stat_compare) { build_stat_compare(k: 'unknown.stat', a: { 'unknown.stat' => [1, 2, 3] }, options: no_more_opt) }

          it { is_expected.to be_falsey }
        end
      end
    end

    describe '#calculate_matrix_values' do
      subject(:matrix_values) { stat_compare.send(:calculate_matrix_values) }

      let(:stat_compare) do
        build_stat_compare(
          k: 'stat',
          a: { 'stat' => [10, 20, 30] },
          b: { 'stat' => [15, 25, 35] }
        )
      end

      it 'calculates matrix values correctly' do
        summary_a, summary_b = matrix_values
        expect(summary_a).to have_attributes(sorted: [10, 20, 30], min: 10, mean: 20, max: 30)
        expect(summary_b).to have_attributes(sorted: [15, 25, 35], min: 15, mean: 25, max: 35)
      end

      context 'when sorted_b is empty' do
        let(:stat_compare) do
          build_stat_compare(
            k: 'stat',
            a: { 'stat' => [10, 20, 30] },
            b: { 'stat' => [] }
          )
        end

        it { is_expected.to be_nil }
      end

      context 'when resizing values' do
        let(:stat_compare) do
          build_stat_compare(
            k: 'stat',
            a: { 'stat' => [1, 2, 3, 4, 5] },
            b: { 'stat' => [15, 25, 35] },
            options: { 'resize' => 3 }
          )
        end

        it 'resizes values' do
          summary_a, _summary_b = matrix_values
          expect(summary_a).to have_attributes(size: 3, sorted: [1, 2, 3])
        end
      end
    end
  end
end
