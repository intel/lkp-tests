require 'spec_helper'
require "#{LKP_SRC}/lib/yaml"

describe 'include/tbox_group/vm' do
  def load_vm_include(model)
    load_yaml("#{LKP_SRC}/include/tbox_group/vm", { 'model' => model })
  end

  it 'requires KVM_GUEST for x86 guests' do
    vm = load_vm_include('qemu-system-x86_64 -enable-kvm -cpu SandyBridge')

    expect(vm['need_kconfig_hw']).to eq([{ 'KVM_GUEST' => 'y' }])
  end

  # KVM_GUEST does not exist on riscv, so requiring it makes the scheduler
  # reject every riscv64 guest job as an unsatisfied kernel config.
  it 'does not require x86-only KVM_GUEST for riscv64 guests' do
    vm = load_vm_include('qemu-system-riscv64 -machine virt')

    expect(vm).not_to include('need_kconfig_hw')
  end
end
