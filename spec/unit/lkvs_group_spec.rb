require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# Every BM/ufs case loops over all uncore dies, so on a many-die host the
# stress cases and check_ufs_elc_low_threshold are each close to half an hour.
# select_lkvs_group() in lib/tests/lkvs.sh lets the job yaml run them as
# separate jobs by rewriting ufs/tests down to one named group.
#
# This extracts and executes the REAL group-selection functions, stubbing only
# die(), and asserts on the tests file they leave behind.
describe 'lkvs ufs case groups' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/lkvs.sh" }
  let(:all_cases) { tests_file.scan(/-t (\w+)$/).flatten }

  let(:tests_file) do
    <<~TESTS
      # TPMI UFS (Uncore Frequency Scaling) driver
      # @hw_dep: general_test.sh -t fms -p "ufs_fms_list" @ CPU Model doesn't support tpmi_ufs

      tpmi_ufs.sh -t check_ufs_unbind_bind
      tpmi_ufs.sh -t check_ufs_device
      tpmi_ufs.sh -t check_ufs_sysfs_attr
      tpmi_ufs.sh -t check_ufs_init_min_max_value
      tpmi_ufs.sh -t check_ufs_min_equals_to_max
      tpmi_ufs.sh -t check_ufs_max_equals_to_min
      tpmi_ufs.sh -t check_ufs_current_dynamic
      # Below two cases verify the efficiency latency control
      tpmi_ufs.sh -t check_ufs_elc_low_threshold
      tpmi_ufs.sh -t check_ufs_elc_high_threshold
    TESTS
  end

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  # returns [cases left in ufs/tests, full file, combined output + status]
  def select_group(group, content)
    Dir.mktmpdir do |dir|
      script = <<~BASH
        die() { echo "die: $*"; exit 99; }
        #{extract_function('lkvs_special_groups')}
        #{extract_function('lkvs_group_cases')}
        #{extract_function('select_lkvs_group')}
        cd #{dir}
        mkdir ufs
        cat >ufs/tests <<'EOF'
        #{content}
        EOF
        test=ufs
        group=#{group}
        (select_lkvs_group) 2>&1
        echo "status=$?"
        cat ufs/tests
      BASH
      out = Bash.run(script, returns: [0, 99])
      body = out.split(/^status=\d+\n/, 2)
      status = out[/^status=(\d+)$/, 1].to_i
      file = body[1].to_s
      [file.scan(/-t (\w+)$/).flatten, file, body[0] + "status=#{status}"]
    end
  end

  it 'basic keeps every case that is not in a split-out group' do
    cases, = select_group('basic', tests_file)

    expect(cases).to eq(%w[check_ufs_unbind_bind check_ufs_device check_ufs_sysfs_attr
                           check_ufs_init_min_max_value check_ufs_elc_high_threshold])
  end

  it 'stress keeps only the min/max/dynamic stress cases' do
    cases, = select_group('stress', tests_file)

    expect(cases).to eq(%w[check_ufs_min_equals_to_max check_ufs_max_equals_to_min check_ufs_current_dynamic])
  end

  it 'elc-low-threshold keeps only that case' do
    cases, = select_group('elc-low-threshold', tests_file)

    expect(cases).to eq(%w[check_ufs_elc_low_threshold])
  end

  it 'runs every case exactly once across the groups' do
    ran = %w[basic stress elc-low-threshold].flat_map { |g| select_group(g, tests_file).first }

    expect(ran.sort).to eq(all_cases.sort)
  end

  it 'keeps the header comments, which runtests reads for its dependence check' do
    _, file, = select_group('stress', tests_file)

    expect(file).to include('# @hw_dep: general_test.sh -t fms')
  end

  it 'puts a case added upstream into basic instead of dropping it' do
    cases, = select_group('basic', "#{tests_file}tpmi_ufs.sh -t check_ufs_new_upstream_case\n")

    expect(cases).to include('check_ufs_new_upstream_case')
  end

  it 'dies on an unknown group' do
    _, _, out = select_group('nonexistent', tests_file)

    expect(out).to match(/die: lkvs: unknown group nonexistent for ufs/)
  end

  it 'dies when upstream renamed a case the group lists' do
    renamed = tests_file.sub('check_ufs_elc_low_threshold', 'check_ufs_elc_low')
    _, _, out = select_group('elc-low-threshold', renamed)

    expect(out).to match(/die: lkvs: case check_ufs_elc_low_threshold of group elc-low-threshold is not in ufs\/tests/)
  end

  it 'leaves the tests file alone when no group is set' do
    cases, = select_group('', tests_file)

    expect(cases).to eq(all_cases)
  end
end
