require 'rspec'

RSpec::Matchers.define :have_ncontents do |expected|
  match do |actual|
    ncontents = actual.ncontents

    # https://www.relishapp.com/rspec/rspec-expectations/v/3-5/docs/custom-matchers/define-diffable-matcher
    # redefine @actual in order for diffable to output clearer message
    @actual = expected.to_h { |expected_k, _expected_v| [expected_k, ncontents.count { |k, _v| k =~ /\.#{expected_k}$/i }] }

    @json_path = actual.json_path

    expected.all? do |expected_k, expected_v|
      expected_v = (expected_v..expected_v) unless expected_v.instance_of? Range

      expected_v.include? @actual[expected_k]
    end
  end

  failure_message do |_actual|
    "expected #{json_path} to have ncontents #{expected}"
  end

  attr_reader :json_path

  diffable
end
