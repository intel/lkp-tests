require 'spec_helper'
require "#{LKP_SRC}/lib/bash"

# check_need_x (lib/run.sh) skips a need_x GUI benchmark before it ever
# starts X on a host whose only display adapter is a BMC remote-management
# graphics chip (e.g. ASPEED AST2xxx) -- these have no monitor attached and
# always fail Xorg's VT switch, which otherwise only shows up as a
# confusing "X connection ... broken" failure well into the test.
describe 'check_need_x' do
  def check_need_x_cmd(fixture, need_x: 'true')
    fixture_dir = File.join(LKP_SRC, 'spec', 'fixtures', 'pci_devices', fixture)
    "source #{LKP_SRC}/lib/debug.sh; source #{LKP_SRC}/lib/run.sh; " \
      "need_x=#{need_x} PCI_DEVICES_DIR=#{fixture_dir} check_need_x 2>&1"
  end

  context 'when the only display adapter is an ASPEED BMC chip' do
    it 'dies with a clear message instead of letting X start' do
      output = Bash.run(check_need_x_cmd('aspeed-bmc-only'), returns: [99])

      expect(output).to include('no display adapter usable for X')
    end
  end

  context 'when there is no display adapter at all' do
    it 'dies with a clear message' do
      output = Bash.run(check_need_x_cmd('no-display'), returns: [99])

      expect(output).to include('no display adapter usable for X')
    end
  end

  context 'when a real GPU is present' do
    it 'does not die' do
      expect { Bash.run(check_need_x_cmd('real-gpu')) }.not_to raise_error
    end
  end

  context 'when a real GPU is present alongside a BMC chip' do
    it 'does not die' do
      expect { Bash.run(check_need_x_cmd('aspeed-and-real-gpu')) }.not_to raise_error
    end
  end

  context 'when need_x is not set' do
    it 'does not check PCI devices at all' do
      expect { Bash.run(check_need_x_cmd('aspeed-bmc-only', need_x: 'false')) }.not_to raise_error
    end
  end
end
