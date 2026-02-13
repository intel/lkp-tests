require 'rspec'

RSpec::Matchers.define :have_contents do |expected|
  match do |actual|
    @actual = actual.respond_to?(:contents) ? actual.contents : actual

    expected = expected.instance_of?(String) ? expected.split("\n") : Array(expected)
    expected = expected.map { |expect| Regexp.new(expect, Regexp::IGNORECASE) }

    @actual.grep(Regexp.union(expected)).size.nonzero?
  end

  failure_message do |actual|
    unmatched = expected.reject { |expect| actual.any? { |content| content =~ expect } }
                        .first(5)
                        .map { |expect| "-#{expect.inspect}" }

    (['expected to have contents', 'Diff:'] + unmatched).join("\n")
  end

  failure_message_when_negated do |actual|
    matched = actual.grep(Regexp.union(expected))
                    .first(5)
                    .map { |content| "+#{content}" }

    (['expected not to have contents', 'Diff:'] + matched).join("\n")
  end
end
