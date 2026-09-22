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

  it 'recognizes list_add/list_del corruption from lib/list_debug.c, which has no "BUG:"/"WARNING:" lead-in' do
    [
      '[   12.345678][    T1] list_add corruption. prev is NULL.',
      '[   12.345678][    T1] list_add corruption. next->prev should be prev (ffff888000000000), but was ' \
      'ffff888000000010. (next=ffff888000000020).',
      '[   12.345678][    T1] list_del corruption, ffff888000000000->next is LIST_POISON1 (dead000000000100)',
      '[   12.345678][    T1] list_del corruption. prev->next should be ffff888000000000, but was ' \
      'ffff888000000010. (prev=ffff888000000020)'
    ].each do |line|
      expect(oops_pattern.pattern(line)).not_to be_nil
    end
  end

  it 'still recognizes BUG:-prefixed lockdep/KCSAN/KFENCE limit-exceeded reports via the generic BUG: catch-all' do
    [
      '[   12.345678][    T1] BUG: MAX_LOCKDEP_KEYS too low!',
      '[   12.345678][    T1] BUG: KCSAN: data-race in foo / bar',
      '[   12.345678][    T1] BUG: KFENCE: out-of-bounds read in foo+0xa6/0x234'
    ].each do |line|
      expect(oops_pattern.pattern(line)).not_to be_nil
    end
  end
end
