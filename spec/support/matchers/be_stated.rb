require 'rspec'

RSpec::Matchers.define :be_stated do
  match do |file_path|
    [file_path, "#{file_path}.json"].all? { |f| File.size?(f) || File.size?("#{f}.gz") || File.size?("#{f}.xz") }
  end
end
