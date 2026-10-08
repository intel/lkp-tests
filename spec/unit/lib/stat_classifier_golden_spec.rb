require 'spec_helper'
require 'yaml'
require "#{LKP_SRC}/lib/stats"

# Pins the pass/fail/skip classification of representative stat names, so a
# change to etc/stat-classifier.yml or to the classifier shows up as an
# explicit, reviewable diff of the fixture.
describe 'stat classification golden corpus' do
  golden = YAML.load_file("#{LKP_SRC}/spec/fixtures/stat_classifier/golden.yaml")
  result_classifier = StatClassifier.new

  it 'has a non-trivial corpus' do
    expect(golden.size).to be > 100
  end

  it 'classifies every stat exactly as recorded' do
    mismatches = golden.filter_map do |stat, expected|
      actual = [StatClassifier.failure_stat?(stat), StatClassifier.pass_stat?(stat), StatClassifier.skip_stat?(stat), result_classifier.type(stat)]
      "#{stat}: expected #{expected}, got #{actual}" if actual != expected
    end

    expect(mismatches).to be_empty
  end
end
