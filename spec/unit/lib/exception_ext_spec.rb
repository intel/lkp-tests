require 'spec_helper'
require 'yaml'
require "#{LKP_SRC}/lib/exception_ext"

describe Exception do
  let(:exception) do
    raise StandardError, 'boom'
  rescue StandardError => e
    e.set_backtrace(['/a/b.rb:1:in `foo\'', '/a/c.rb:2:in `bar\''])
    e
  end

  describe '#formatted_body' do
    it 'indents backtrace frames with spaces, not a tab' do
      expect(exception.formatted_body).to all(start_with('  from '))
      expect(exception.formatted_body.join).not_to include("\t")
    end
  end

  describe '#call_stack' do
    # a tab character here would make libyaml refuse a literal block scalar
    # and fall back to an escaped/quoted one-liner (unreadable call_stack)
    it 'renders as a readable literal block scalar when dumped to YAML' do
      yaml = { call_stack: exception.call_stack.join("\n") }.to_yaml
      expect(yaml).to include('call_stack: |')
    end
  end
end
