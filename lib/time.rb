# Compatibility shim: require this file instead of active_support/time directly.
#
# activesupport-7.2 has two top-level requirements that fail on Ruby 3.3+:
#   - time_with_zone.rb calls YAML.load_tags  (psych no longer auto-required)
#   - conversions.rb does alias_method :rfc3339, :xmlschema  (xmlschema removed)
require 'time'
require 'psych'
require 'yaml'
YAML = Psych unless defined?(YAML) # guard against partial yaml load leaving YAML undefined

class Time
  unless method_defined?(:xmlschema)
    if method_defined?(:iso8601)
      alias xmlschema iso8601
    else
      # Ruby 3.3+ with time gem >= 0.4.0: provide a minimal stand-in until
      # active_support/time loads and re-opens Time with the full implementation.
      def xmlschema(fraction_digits = 0)
        s = strftime('%Y-%m-%dT%H:%M:%S')
        s += format('.%0*d', fraction_digits, (usec.to_r / (10**(6 - fraction_digits))).round) if fraction_digits.positive?
        s + (utc? ? 'Z' : strftime('%:z'))
      end
    end
  end
end

# active_support/deprecator was introduced in activesupport 7.1.
# activesupport >= 7.2 calls ActiveSupport.deprecator at runtime (inside
# preserve_timezone), but the file is absent in 6.x, so guard with rescue.
begin
  require 'active_support/deprecation'
  require 'active_support/deprecator'
rescue LoadError
  nil
end

# active_support/time.rb never requires active_support/isolated_execution_state
# itself -- it is normally pulled in only via the top-level active_support.rb
# autoload table. Requiring active_support/time directly (as this shim and
# every caller of it do) skips that autoload registration, so any Date/Time
# method that reads ActiveSupport::IsolatedExecutionState (e.g. beginning_of_week,
# prev_week, beginning_of_month) raises "uninitialized constant" at call time,
# not at load time. Require it explicitly to guarantee the constant exists.
begin
  require 'active_support/isolated_execution_state'
rescue LoadError
  nil
end
require 'active_support/time'
