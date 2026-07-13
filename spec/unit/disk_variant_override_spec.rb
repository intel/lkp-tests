require 'spec_helper'
require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/job"

# Regression guard for the class of bug where a disk-variant job YAML
# (e.g. "<suite>-1ssd.yaml") includes a multi-document base file via
# "<<: <suite>.yaml" and overrides "disk:" with a plain top-level line
# appended after the include. That override is a textual append landing
# after the ENTIRE included file, so it only reaches whichever "---"
# document it happens to land in (usually the last one), leaving every
# other document silently inheriting the base file's original disk value.
#
# See jobs/stress-ng/stress-ng-part6-1ssd.yaml (fixed by switching to the
# standard-YAML flow-mapping "<<: {file: base.yaml, disk: 'X'}" override
# form) and jobs/ltp/ltp-syscalls-1ssd.yaml (fixed by extracting the
# outlier document into its own standalone file) for the two known fix
# patterns.
describe 'disk-variant job YAML include overrides' do
  Dir[LKP::Path.src('jobs', '**', '*.yaml')].each do |job_yaml|
    content = File.read(job_yaml)
    first_line = content.lines.find { |l| !l.strip.empty? }
    next unless first_line&.start_with?('<<:')

    # Only match a plain scalar override on the same line (e.g. "disk: 1SSD",
    # "disk: '1SSD'", or the flow-mapping "{file: ..., disk: '1SSD'}", where
    # "disk:" may be followed by other keys rather than ending the line) - a
    # bare "disk:" with the value on a following indented line is a nested
    # hash (e.g. "nr_ssd: 1"), a different feature entirely.
    inline_disk_match = first_line.match(/disk:[ \t]*['"]?([\w%]+)['"]?/)
    separate_line_match = content.match(/^disk:[ \t]*['"]?([\w%]+)['"]?[ \t]*$/)
    expected_disk = inline_disk_match ? inline_disk_match[1] : separate_line_match&.[](1)
    next unless expected_disk

    it "applies disk: #{expected_disk} to every document in #{job_yaml}" do
      job = Job.open(job_yaml, expand_template: true)
      disks = []
      job.each_jobs do |j|
        jc = j.dup
        jc.expand_params(run_scripts: false)
        disks << jc['disk']
      end

      expect(disks.uniq).to eq [expected_disk]
    end
  end
end
