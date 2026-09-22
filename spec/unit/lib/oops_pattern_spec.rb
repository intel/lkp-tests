require 'spec_helper'
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/lkp_pattern"

describe 'etc/oops-pattern' do
  let(:oops_pattern) { LKP::Pattern.new(LKP::Path.etc('oops-pattern')) }

  it 'recognizes the file:line-before-"at" WARN format newer kernels emit' do
    line = '  [  141.464494][    T0] WARNING: kernel/trace/trace_events.c:420 ' \
           'at test_double_dereference.cold+0x39/0x49, CPU#0: swapper/0/0'

    expect(oops_pattern.pattern(line)).not_to be_nil
  end

  it 'still recognizes the older "CPU: N PID: M at file:line" ordering' do
    line = 'WARNING: CPU: 0 PID: 5 at drivers/foo.c:99 foo_bar+0x1/0x2()'

    expect(oops_pattern.pattern(line)).not_to be_nil
  end

  it 'does not match an unrelated lkp harness banner line' do
    line = '  [   42.122603][  T246] INFO: lkp CACHE_DIR is /tmp/cache'

    expect(oops_pattern.pattern(line)).to be_nil
  end
end
