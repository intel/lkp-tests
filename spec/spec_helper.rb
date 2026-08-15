LKP_SRC ||= ENV['LKP_SRC'] || File.expand_path('..', __dir__)

require 'rspec'
require "#{LKP_SRC}/lib/lkp_tmpdir"
require "#{LKP_SRC}/lib/log"

# Suppress MailLogHandler for all unit tests. LKP::Notifier sends real emails
# when log_warn/log_error are called and the alert log directory exists (i.e.
# on deployed servers). This only applies when LKP_SRC resolves to a runtime
# tree whose lib/log.rb defines the mail-integrated LKP::Log class rather than
# this repo's own plain Log class.
LKP::MailLogHandler.prepend(Module.new { def publish(*) = nil }) if defined?(LKP::MailLogHandler)

$LOAD_PATH.delete_if { |p| File.expand_path(p) == File.expand_path('./lib') }

if ENV['GENERATE_COVERAGE'] == 'true'
  require 'simplecov'
  require 'simplecov-rcov'
  SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
  SimpleCov.start
end

Dir[File.join(LKP_SRC, 'spec', 'support', '**', '*.rb')].each { |f| require f }
