require 'spec_helper'
require "#{LKP_SRC}/lib/dmesg"

describe 'Dmesg' do
  describe 'analyze_error_id' do
    it 'compresses corrupted low memeory messages' do
      line, bug_to_bisect = analyze_error_id '[   61.268659] Corrupted low memory at ffff880000007b08 (7b08 phys) = 27200c000000000'
      expect(line).to eq 'Corrupted_low_memory_at#(#phys)='
      expect(bug_to_bisect).to eq 'Corrupted low memory at .* phys)'
    end

    it 'compresses nbd messages' do
      ['[   31.694592] ADFS-fs error (device nbd10): adfs_fill_super: unable to read superblock',
       '[   31.971391] ADFS-fs error (device nbd7): adfs_fill_super: unable to read superblock'].each do |line|
        line, bug_to_bisect = analyze_error_id line
        expect(line).to eq 'ADFS-fs_error(device_nbd#):adfs_fill_super:unable_to_read_superblock'
        expect(bug_to_bisect).to eq 'ADFS-fs error (device .* adfs_fill_super: unable to read superblock'
      end

      ['[   33.167933] block nbd11: Attempted send on closed socket',
       '[   33.171522] block nbd1: Attempted send on closed socket'].each do |line|
        line, _bug_to_bisect = analyze_error_id line
        expect(line).to eq 'block_nbd#:Attempted_send_on_closed_socket'
      end

      line, _bug_to_bisect = analyze_error_id '[   27.617020] EXT4-fs (nbd3): unable to read superblock'
      expect(line).to eq 'EXT4-fs(nbd#):unable_to_read_superblock'

      line, _bug_to_bisect = analyze_error_id '[   29.177529] REISERFS warning (device nbd3): sh-2006 read_super_block: bread failed (dev nbd3, block 2, size 4096)'
      expect(line).to eq 'REISERFS_warning(device_nbd#):sh-#read_super_block:bread_failed(dev_nbd#,block#,size#)'
    end

    it 'compresses set_feature messages' do
      line, _bug_to_bisect = analyze_error_id '[   14.754513] plip0: set_features() failed (-1); wanted 0x0000000000004000, left 0x0000000000004800'
      expect(line).to eq 'plip#:set_features()failed(-#);wanted#,left'

      line, _bug_to_bisect = analyze_error_id '[   14.626736] bcsf1: set_features() failed (-1); wanted 0x0000000000004000, left 0x0000000000004800'
      expect(line).to eq 'bcsf#:set_features()failed(-#);wanted#,left'
    end

    it 'compresses parport messages' do
      line, _bug_to_bisect = analyze_error_id '[    7.895752] parport0: cannot grant exclusive access for device spi-lm70llp'
      expect(line).to eq 'parport#:cannot_grant_exclusive_access_for_device_spi-lm#llp'
    end

    it 'slab cache affected' do
      {
        '[   32.298491][  T896] BUG kmalloc-8: Right Redzone overwritten' => 'BUG_kmalloc-#:Right_Redzone_overwritten',
        '[   14.476643][    C0] BUG kmalloc-512 (Tainted: G S      W       T ): Right Redzone overwritten' => 'BUG_kmalloc-#:Right_Redzone_overwritten',
        '[  264.548980][    C1] BUG kmalloc-rnd-02-96 (Tainted: G        W       TN): Freechain corrupt' => 'BUG_kmalloc-rnd-#-#:Freechain_corrupt'
      }.each do |line, expected|
        line, _bug_to_bisect = analyze_error_id line
        expect(line).to eq expected
      end
    end

    it 'normalizes the newer file:line-before-"at" WARNING format to the same id as the older ordering' do
      old_line = '[   11.858566][    T1] WARNING: CPU: 0 PID: 11 at kernel/locking/lockdep.c:3536 lock_release+0x179/0x3b7'
      new_line = '[   11.858566][    T1] WARNING: kernel/locking/lockdep.c:3536 at lock_release+0x179/0x3b7, CPU#0: swapper/0/11'

      old_id, old_bisect = analyze_error_id old_line
      new_id, new_bisect = analyze_error_id new_line

      expect(new_id).to eq old_id
      expect(new_bisect).to eq old_bisect
      expect(new_id).to eq 'WARNING:at_kernel/locking/lockdep.c:#lock_release'
    end

    it 'keeps the full function name of a .cold-suffixed WARNING in the new format (was truncated to "cold")' do
      line = '[  141.464494][    T0] WARNING: kernel/trace/trace_events.c:420 at ' \
             'test_double_dereference.cold+0x39/0x49, CPU#0: swapper/0/0'

      id, bisect = analyze_error_id line

      expect(id).to include('test_double_dereference.cold')
      expect(bisect).to eq 'WARNING:.* at .* test_double_dereference.cold+0x'
    end

    it 'does not truncate a .cold-suffixed function name at the dot in the generic fallback path' do
      # BUG: unable to handle kernel NULL pointer dereference falls through
      # to oops_to_bisect_pattern's word scan rather than a dedicated
      # handle_* branch -- confirm its function-name capture keeps the dot
      # too, not just the WARNING-specific branch above.
      line = 'some_other_bug_marker at print_circular_bug.cold+0x119/0x121'

      expect(oops_to_bisect_pattern(line)).to include('print_circular_bug.cold+0x')
    end
  end

  describe 'grep_crash_head' do
    # mm/page_alloc.c's warn_alloc() is shared by 4 callers (page allocation
    # failure, its own separate stall warning, mm/vmalloc.c's error,
    # mm/sparse-vmemmap.c's failure), each printed with the triggering
    # process's comm followed by the same "mode:...nodemask=" suffix. Two
    # different callers hitting with the *same* gfp_mask must still end up
    # as different stats/bisect ids -- the caller's own message is what
    # actually distinguishes the bug, not the shared mode/nodemask suffix.
    it 'keeps different warn_alloc() callers distinct even when they share the same gfp_mask' do
      Tempfile.create('dmesg-warn-alloc') do |f|
        f.puts '[   10.000000] cc1: page allocation stall for 10 secs: order:0, mode:0x2cc0(GFP_KERNEL|__GFP_ZERO), nodemask=(null)'
        f.puts '[   20.000000] cc1: vmemmap alloc failure: order:0, mode:0x2cc0(GFP_KERNEL|__GFP_ZERO), nodemask=(null)'
        f.flush

        oops_map = grep_crash_head(f.path)
        error_ids = oops_map.keys.map { |key| analyze_error_id(key)[0] }

        expect(error_ids.uniq.size).to eq(2)
      end
    end

    it 'recognizes the newer file:line-before-"at" WARNING format newer kernels emit' do
      Tempfile.create('dmesg-warning-new-order') do |f|
        f.puts '[  141.464494][    T0] WARNING: kernel/trace/trace_events.c:420 at ' \
               'test_double_dereference.cold+0x39/0x49, CPU#0: swapper/0/0'
        f.flush

        oops_map = grep_crash_head(f.path)

        expect(oops_map).not_to be_empty
        expect(analyze_error_id(oops_map.keys.first)[0]).to include('test_double_dereference.cold')
      end
    end

    it 'does not treat an unrelated lkp harness banner line as an oops' do
      Tempfile.create('dmesg-banner') do |f|
        f.puts '[   42.122603][  T246] INFO: lkp CACHE_DIR is /tmp/cache'
        f.flush

        expect(grep_crash_head(f.path)).to be_empty
      end
    end

    # drivers/edac/edac_mc.c's edac_ce_error()/edac_ue_error() are the
    # shared reporting path for every EDAC memory-controller driver
    # (amd64_edac, skx_edac, sb_edac, ...) -- a corrected or uncorrected
    # ECC error is real kernel-detected hardware memory corruption even
    # when it doesn't panic the boot.
    it 'recognizes an EDAC corrected/uncorrected memory error report' do
      Tempfile.create('dmesg-edac') do |f|
        f.puts '[   12.345678] EDAC MC0: 1 CE row 2, chan 1 on mc#0csrow#2channel#1 ' \
               '(csrow:2,channel:1 page:0x38a35 offset:0x0 grain:32 syndrome:0x0)'
        f.flush

        expect(grep_crash_head(f.path)).not_to be_empty
      end
    end

    # arch/x86/kernel/cpu/mce/core.c's __print_mce() (and drivers/edac/
    # mce_amd.c's AMD decode chain) print every logged machine check
    # under the shared "[Hardware Error]: " (HW_ERR) prefix, whether or
    # not the MCE goes on to panic the kernel.
    it 'recognizes a machine-check "[Hardware Error]:" report' do
      Tempfile.create('dmesg-mce') do |f|
        f.puts '[   45.123456] [Hardware Error]: CPU 3: Machine Check: 0 Bank 4: b200000000070f0f'
        f.flush

        expect(grep_crash_head(f.path)).not_to be_empty
      end
    end

    # mm/memory-failure.c's action_result() is the shared per-event
    # summary for every hwpoison recovery path (GHES/APEI firmware-first
    # memory errors, MCE recovery, and deliberate hwpoison testing).
    it 'recognizes a memory-failure recovery-action report' do
      Tempfile.create('dmesg-memory-failure') do |f|
        f.puts '[   67.891234] Memory failure: 0x38a35: recovery action for dirty LRU page: Recovered'
        f.flush

        expect(grep_crash_head(f.path)).not_to be_empty
      end
    end
  end

  describe 'get_crash_calltraces' do
    files = Dir.glob "#{LKP_SRC}/spec/fixtures/dmesg/calltrace/dmesg-*"
    files.each do |file|
      it "extracts call trace chunks from #{File.basename file}" do
        actual = get_crash_calltraces file
        expected = File.read(file.sub('dmesg-', 'calltrace-')).split(/^---\n/)

        expect(expected).to eq actual
      end
    end
  end

  describe 'get_content' do
    # A kernel that floods printk (e.g. a runaway OOM-killer loop) can
    # produce a kmsg/dmesg capture orders of magnitude larger than any
    # real crash needs. Loading the whole file with File.read then risks
    # exhausting memory in the stats-extraction step itself, turning one
    # runaway kernel log into a "fail to extract stats" failure. Verify
    # get_content caps how much of an oversized file it reads, using a
    # small custom max_size so the spec doesn't need a huge fixture.
    it 'reads the whole file when it is within the size limit' do
      Tempfile.create('dmesg-small') do |f|
        f.write("head-marker#{'x' * 20}tail-marker")
        f.flush

        content = get_content(f.path, 1024)

        expect(content).to include('head-marker')
        expect(content).to include('tail-marker')
      end
    end

    it 'reads only the tail of a file larger than the size limit' do
      Tempfile.create('dmesg-large') do |f|
        f.write("head-marker#{'x' * 200}tail-marker")
        f.flush

        content = get_content(f.path, 50)

        expect(content).not_to include('head-marker')
        expect(content).to include('tail-marker')
        expect(content.bytesize).to eq 50
      end
    end
  end
end
