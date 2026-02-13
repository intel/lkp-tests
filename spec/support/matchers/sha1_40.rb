require 'rspec'

RSpec::Matchers.define :be_sha1_40 do # rubocop:disable Naming/VariableNumber
  match do |commit|
    commit =~ /^[\da-f]{40}$/
  end
end
