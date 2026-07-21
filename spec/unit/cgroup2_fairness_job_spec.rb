require 'spec_helper'
require "#{LKP_SRC}/lib/lkp_path"

# Regression guard for cgroup2 fairness jobs (e.g.
# jobs/hackbench/hackbench-cgroup2-fairness.yaml,
# jobs/schbench/schbench-cgroup2-fairness.yaml,
# jobs/fio-basic/fio-basic-cgroup2-fairness.yaml): each such job creates
# "cgroup2.cg_count" sibling cgroups and relies on "nr_instances" matching
# it 1:1 so every sibling gets its own instance_id, and on any
# "<param>_by_instance" override list having no more entries than there
# are siblings to apply them to. A future edit that changes cg_count or
# nr_instances without updating the other would silently leave some
# cgroups unexercised or some instances without their own cgroup.
describe 'cgroup2 fairness job YAML' do
  Dir[LKP::Path.src('jobs', '**', '*.yaml')].each do |job_yaml|
    # A handful of job YAMLs embed ERB (e.g. case/when blocks in jobs/pts,
    # jobs/fsmark) and aren't valid plain YAML on their own; skip those, as
    # a cgroup2 fairness job has no reason to need ERB for this check.
    documents = begin
      YAML.load_stream(File.read(job_yaml))
    rescue Psych::SyntaxError
      next
    end

    documents.each do |document|
      next unless document.is_a?(Hash)

      cgroup2 = document['cgroup2']
      nr_instances = document['nr_instances']
      next unless cgroup2.is_a?(Hash) && cgroup2['cg_count'] && nr_instances

      cg_count = cgroup2['cg_count'].to_i

      it "matches nr_instances to cgroup2.cg_count in #{File.basename(job_yaml)}" do
        expect(nr_instances.to_i).to eq(cg_count)
      end

      document.each do |key, value|
        next unless key.to_s.end_with?('_by_instance')

        it "keeps #{key} within cg_count in #{File.basename(job_yaml)}" do
          overrides = value.to_s.split
          expect(overrides.size).to be <= cg_count
        end
      end
    end
  end
end
