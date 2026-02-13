require 'spec_helper'

describe 'stress-ng' do
  Dir[LKP::Path.src('jobs', 'stress-ng*.yaml')].each do |job_yaml|
    it "has sorted test names in #{job_yaml}" do
      load_values_from_job_yamls(File.basename(job_yaml, '.yaml'), include_comment: false) do |document|
        expect(document['stress-ng']['test']).to be_sorted
      end
    end
  end
end
