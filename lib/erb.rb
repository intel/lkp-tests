#!/usr/bin/env ruby

require 'erb'
require 'yaml'

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/hashugar"

# bring in functions usable for ERB code segments
require "#{LKP_SRC}/lib/unit"

# Support references to variables (with real values) defined in the same job.
#
# This follows the KISS principle: just good enough to meet simple requirements.
# It's anti-intuitive and hence discouraged to write complex macro/templates
# in job YAML anyway.
#
# The implementation is not clean in several ways,
#
# - the ERB code reduction gsubs do not handle ^%% <%% escaped tags
#   yet to see who will use such strings in YAML
#
# - the ERB code reduced YAML may be an invalid YAML
#   YAML.load will fail and you are probably writing too complex templates
#
def expand_erb(template, context_hash = {})
  return template unless template =~ /^%|<%/

  yaml = template.remove(/<%.*?%>/m).remove(/^%[^>].*$/)
  job = YAML.load(yaml) || {}
  job.merge!(context_hash)
  context = Hashugar.new(job).instance_eval { binding }

  erb = if RUBY_VERSION < '2.6'
          ERB.new(template, nil, '%')
        else
          ERB.new(template, trim_mode: '%')
        end

  erb.result(context)
end

# support: {{ expression }}
# make it a block literal to avoid YAML parse errors
# http://yaml.org/YAML_for_ruby.html#blocks
def literal_double_braces(yaml)
  yaml.gsub(/^([^\n]*?[:-]\s+)({{.*?}})/m) do |_match|
    indent = ' ' * ($1.size + 1)
    "#{$1}|\n#{$2.gsub(/^/, indent)}"
  end
end

def expand_expression(job, expr, file)
  # puts job, expr
  context = Hashugar.new(job).instance_eval { binding }
  context.eval(expr, file)
end
