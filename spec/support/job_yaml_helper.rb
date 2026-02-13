LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__, 2)

require 'rspec'
require 'yaml'
require "#{LKP_SRC}/lib/lkp_path"

# Load values from job YAML files.
#
# If include_comment is true, it uncomments list items that are commented out.
# This is useful for including disabled test cases in the analysis.
# Only supports the comment style: # - item
#
# Example:
#   In the following YAML, 'sg', 'null', and 'net' will be treated as test cases
#   if include_comment is true.
#
#   fio-setup-basic:
#     ioengine:
#       - ftruncate
#       # - sg
#       - vsync
#       # test purpose,ignore
#       # - "null"
#       # requires two servers, ignore
#       # - net
def load_values_from_job_yamls(job_yaml_pattern, include_comment: true)
  contents = Dir[LKP::Path.src('jobs', "#{job_yaml_pattern}.yaml")].flat_map do |file|
    content = File.read(file)
    content = content.gsub(/#(\s*)- /, '- ') if include_comment

    YAML.load_stream(content)
  end

  contents.flat_map do |content|
    yield content if block_given?
  end
end
