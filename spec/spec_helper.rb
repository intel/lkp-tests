LKP_SRC ||= ENV['LKP_SRC'] || File.expand_path('..', __dir__)

require 'rspec'
require "#{LKP_SRC}/lib/lkp_tmpdir"

$LOAD_PATH.delete_if { |p| File.expand_path(p) == File.expand_path('./lib') }

if ENV['GENERATE_COVERAGE'] == 'true'
  require 'simplecov'
  require 'simplecov-rcov'
  SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
  SimpleCov.start
end

Dir[File.join(LKP_SRC, 'spec', 'support', '**', '*.rb')].each { |f| require f }
