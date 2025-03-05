#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/lkp_path"

class KernelTag
  include Comparable
  attr_reader :kernel_tag

  def initialize(kernel_tag)
    @kernel_tag = kernel_tag
  end

  # Convert kernel_tag to number, major * 1_000_000_000 + minor * 1_000_000 + patch_level * 1_000 + prerelease
  # If kernel is not a rc version. Set prerelease as 999.
  #   kernel_tag: v5.7-rc3  ==> 5 * 1000000000 + 7 * 1000000 + 3                = 5007000003
  #   kernel_tag: v5.7      ==> 5 * 1000000000 + 7 * 1000000 + 999              = 5007000999
  #   kernel_tag: v5.7.268  ==> 5 * 1000000000 + 7 * 1000000 + 268 * 1000 + 999 = 5007268999
  #   kernel_tag: v4.20-rc2 ==> 4 * 1000000000 + 20 * 1000000 + 2               = 4020000002
  def numerize_kernel_tag(kernel_tag)
    match = kernel_tag.match(/v(?<major_version>[0-9])\.(?<minor_version>\d+)\.?(?<patch_level>\d+)?(?:-rc(?<prerelease_version>\d+))?/)

    match[:major_version].to_i * 1_000_000_000 + \
      match[:minor_version].to_i * 1_000_000 + \
      match[:patch_level].to_i * 1_000 + \
      (match[:prerelease_version] || 999).to_i
  end

  def <=>(other)
    numerized_kernel_version1 = numerize_kernel_tag(@kernel_tag)
    numerized_kernel_version2 = numerize_kernel_tag(other.kernel_tag)

    numerized_kernel_version1 <=> numerized_kernel_version2
  end

  class << self
    def kconfigs_yaml
      LKP::Path.src('etc', 'kconfigs.yaml')
    end
  end
end

def kernel_match_version?(kernel_version, expected_kernel_versions)
  kernel_version = KernelTag.new(kernel_version)

  expected_kernel_versions.all? do |expected_kernel_version|
    match = expected_kernel_version.match(/(?<operator>==|!=|<|<=|>|>=)?\s*(?<kernel_tag>v[0-9]\.\d+(?:\.\d+)?(?:-rc\d+)?)/)
    raise Job::SyntaxError, "Wrong syntax of kconfig setting: #{expected_kernel_versions}" if match.nil? || match[:kernel_tag].nil?

    operator = match[:operator] || '>='

    # rli9 FIXME: hack code to handle <=
    # Take below example, MEMORY_HOTPLUG_SPARSE is moved in 5.16-rc1, thus we configure
    # as <= 5.15. But we use rc_tag to decide the kernel of commit, 50f9481ed9fb or other
    # commit now use kernel v5.15 to compare. This matches the <= and expects MEMORY_HOTPLUG_SPARSE
    # is y, which leads to job filtered wrongly on these commits.
    #
    # fa55b7dcdc43 ("Linux 5.16-rc1")
    # c55a04176cba ("Merge tag 'char-misc-5.16-rc1' ...")
    # 50f9481ed9fb ("mm/memory_hotplug: remove CONFIG_MEMORY_HOTPLUG_SPARSE")
    # 8bb7eca972ad ("Linux 5.15")
    #
    # To workaround this, change operator to < to mismatch the kernel
    operator = '<' if operator == '<='

    kernel_version.method(operator).call(KernelTag.new(match[:kernel_tag]))
  end
end
