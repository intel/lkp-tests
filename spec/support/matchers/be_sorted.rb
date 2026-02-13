require 'rspec'

RSpec::Matchers.define :be_sorted do
  match do |actual|
    actual == actual.sort
  end

  failure_message do |actual|
    sorted = actual.sort

    actual, sorted = actual.zip(sorted).reject { |a, b| a == b }.transpose

    "expected to be sorted, but it was not.\n#{['Diff:', "-#{actual}", "+#{sorted}"].join("\n")}"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would not be sorted"
  end
end
