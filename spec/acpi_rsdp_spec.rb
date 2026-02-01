require 'spec_helper'
require "#{LKP_SRC}/lib/bash"

describe 'acpi_rsdp' do
  it 'get_acpi_rsdp_from_dmesg' do
    artifact = File.join(LKP_SRC, 'spec', 'acpi_rsdp_dmesg')

    expect(Bash.run("source #{LKP_SRC}/lib/kexec.sh; get_acpi_rsdp_from_dmesg #{artifact}; echo $acpi_rsdp")).to eq('0x699fd014')
  end
end
