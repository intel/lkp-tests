require 'rspec'

RSpec::Matchers.define :be_empty_array do
  match(&:empty?)

  failure_message do |actual|
    "expected: array to be empty\n     got: #{actual.join("\n          ")}"
  end
end
