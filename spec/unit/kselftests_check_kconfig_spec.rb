require 'spec_helper'
require 'tmpdir'
require "#{LKP_SRC}/lib/bash"

# CONFIG_ENABLE_DEFAULT_TRACERS has "depends on !GENERIC_TRACER", so it can
# never be enabled in a kernel that has any other tracer (e.g. FUNCTION_TRACER)
# turned on, even though the tracing the landlock trace tests need is present.
# check_kconfig must not emit a "miss config" warning for it in that case, but
# must still warn when the kernel has neither the symbol nor GENERIC_TRACER.
#
# This extracts and executes the REAL check_kconfig function body.
describe 'kselftests check_kconfig CONFIG_ENABLE_DEFAULT_TRACERS' do
  let(:script_path) { "#{LKP_SRC}/lib/tests/kselftests.sh" }
  let(:dependent_config) { "CONFIG_AUDIT=y\nCONFIG_ENABLE_DEFAULT_TRACERS=y\nCONFIG_FTRACE=y\n" }

  def extract_function(name)
    src = File.read(script_path)
    match = src[/^#{name}\(\)\n\{.*?\n\}\n/m]
    raise "could not find function #{name} in #{script_path}" unless match

    match
  end

  def check_kconfig(kernel_config)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'dependent'), dependent_config)
      File.write(File.join(dir, 'kernel'), kernel_config)

      Bash.run("cd #{dir} && #{extract_function('check_kconfig')}\ncheck_kconfig dependent kernel")
    end
  end

  it 'does not warn when GENERIC_TRACER makes the symbol unselectable' do
    output = check_kconfig("CONFIG_AUDIT=y\nCONFIG_FTRACE=y\nCONFIG_GENERIC_TRACER=y\n")

    expect(output).not_to include('ENABLE_DEFAULT_TRACERS')
  end

  it 'still warns when neither the symbol nor GENERIC_TRACER is set' do
    output = check_kconfig("CONFIG_AUDIT=y\nCONFIG_FTRACE=y\n")

    expect(output).to include('LKP WARN miss config CONFIG_ENABLE_DEFAULT_TRACERS=')
  end

  it 'still warns about other missing kconfigs' do
    output = check_kconfig("CONFIG_AUDIT=y\nCONFIG_GENERIC_TRACER=y\n")

    expect(output).to include('LKP WARN miss config CONFIG_FTRACE=')
  end
end
