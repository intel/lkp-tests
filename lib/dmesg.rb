#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/yaml"
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/string"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/log"
require "#{LKP_SRC}/lib/programs"
require "#{LKP_SRC}/lib/lkp_pattern"
require "#{LKP_SRC}/lib/tests/stats"

LKP_SRC_ETC ||= LKP::Path.src('etc')

# /c/linux% git grep '"[a-z][a-z_]\+%d"'|grep -o '"[a-z_]\+'|cut -c2-|sort -u
LINUX_DEVICE_NAMES = IO.read("#{LKP_SRC_ETC}/linux-device-names").split("\n")
LINUX_DEVICE_NAMES_RE = /\b(#{LINUX_DEVICE_NAMES.join('|')})\d+/.freeze

require 'fileutils'
require 'tempfile'

def fixup_dmesg(line)
  line.chomp!

  # remove absolute path names
  line.sub!(%r{/kbuild/src/[^/]+/}, '')
  line.sub!(%r{/tmp/kbuild/src/[^/]+/}, '')

  line.sub!(/\.(isra|constprop|part)\.[0-9]+\+0x/, '+0x')

  # break up mixed messages
  case line
  when /^<[0-9]>|^(kern  |user  |daemon):......: / # rubocop:disable Lint/EmptyWhen
    # line keeps no change
  when /(.+)(\[ *[0-9]{1,6}\.[0-9]{6}\] .*)/
    line = "#{$1}\n#{$2}"
  end

  line
end

def fixup_dmesg_file(dmesg_file)
  tmpfile = Tempfile.new '.fixup-dmesg-', File.dirname(dmesg_file)
  dmesg_lines = []
  File.open(dmesg_file, 'rb') do |f|
    f.each_line do |line|
      line = fixup_dmesg(line)
      dmesg_lines << line
      tmpfile.puts line
    end
  end
  tmpfile.chmod 0o664
  tmpfile.close
  FileUtils.mv tmpfile.path, dmesg_file, force: true
  dmesg_lines
end

# "grep -B1 | grep -v" to get the functions called by them,
# which will hopefully be stable and representive.
CALLTRACE_COMMON_CONTEXT = "
  do_one_initcall|
  do_basic_setup|
  kernel_init_freeable|
  kernel_init|
  kthread|
  kernel_thread|
  process_one_work|
  notifier_call_chain|
".freeze

CALLTRACE_PATTERN = /(
  #{CALLTRACE_COMMON_CONTEXT}
  SyS_[a-z0-9_]+
)\+0x/x.freeze

CALLTRACE_IGNORE_PATTERN = /(
  #{CALLTRACE_COMMON_CONTEXT}
  worker_thread|
  warn_slowpath_.*
)\+0x/x.freeze

OOM_PATTERN = /invoked oom-killer: gfp_mask=|Out of memory and no killable processes.../.freeze

def grep_cmd(dmesg_file)
  if dmesg_file =~ /\.xz$/
    'xzgrep'
    # cat = 'xzcat'
  else
    'grep'
    # cat = 'cat'
  end
end

def concat_context_from_dmesg(dmesg_file, line)
  line = line.resolve_invalid_bytes
  if line =~ /(possible recursive locking detected|possible circular locking dependency detected)/
    lines = `#{grep_cmd(dmesg_file)} -A30 -Fx "#{line.chomp}" #{dmesg_file} | grep -m4 -e "trying to acquire lock" -e "already holding lock" -e "at: .*" | sed 's/^.* at:/at:/'`.chomp.split("\n")
    unless lines.empty?
      new_line = "#{line.chomp} #{lines.map { |l| l.sub(/^\[.*\] /, '') }.join(' ')}"
      return [line, new_line]
    end
  end
  line
end

def grep_crash_head(dmesg_file)
  raw_oops = `#{grep_cmd(dmesg_file)} -a -E -e \\\\+0x -f #{LKP_SRC_ETC}/oops-pattern #{dmesg_file} | grep -v -E -f #{LKP_SRC_ETC}/oops-pattern-ignore`

  return {} if raw_oops.empty?

  oops_map = {}

  prev_line = nil
  has_oom = false

  add_one_calltrace = lambda do |line|
    break if has_oom
    break if line =~ CALLTRACE_IGNORE_PATTERN
    break unless line =~ />\] ([a-zA-Z0-9_.]+)\+0x[0-9a-fx\/]+/

    oops_map["calltrace:#{$1}"] ||= line
  end

  raw_oops.each_line
          .flat_map { |l| concat_context_from_dmesg(dmesg_file, l) }
          .each do |line|
    case line
    when LKP::OopsPattern.instance.regexp
      oops_map[$1] ||= line

      has_oom = true if line =~ OOM_PATTERN
    when /\+0x/
      next if line.index ' ? '

      if line =~ CALLTRACE_PATTERN
        add_one_calltrace[prev_line] unless line.index('SyS_')
        add_one_calltrace[line]
        prev_line = nil
      else
        prev_line = line
      end
    else
      log_warn "oops pattern mismatch: #{line}"
    end
  end

  oops_map
end

def grep_printk_errors(kmsg_file, kmsg)
  return '' if ENV.fetch('RESULT_ROOT', '').index '/trinity/'

  grep = if kmsg_file =~ /\.xz$/
           'xzgrep'
         else
           'grep'
         end

  if kmsg_file =~ /\bkmsg\b/
    # the kmsg file is dumped inside the running kernel
    oops = `#{grep} -a -E -e 'segfault at' -e '^<[0123]>' -e '^kern  :(err   |crit  |alert |emerg ): ' #{kmsg_file} |
      sed -r 's/\\x1b\\[([0-9;]+m|[mK])//g' |
      grep -a -v -E -f #{LKP_SRC_ETC}/oops-pattern |
      grep -a -v -F -f #{LKP_SRC_ETC}/kmsg-denylist.raw;
      grep "Kernel tests: Boot OK" #{kmsg_file};
      grep -Eo "[^ ]* runtime error:.*" #{kmsg_file} | sed 's/^/sanitizer./g';
      grep -Eo -e "Direct leak of .*allocated from:" -e "Indirect leak of .*allocated from:" -e "#[0-5] 0x[0-9a-z]{12} in .*" #{kmsg_file} |
      sed 's/^Indirect leak.*/|sanitizer.indirect_leak/g' | sed 's/^Direct leak.*/|sanitizer.direct_leak/g' |
      sed "s/#[0-5] 0x[0-9a-z]\\{12\\} in //g" | awk '{print $1}' | tr '\n' '/' | tr '|' '\n' | sed 's|/$||'`
  else
    return '' unless File.exist?("#{KTEST_USER_GENERATED_DIR}/printk-error-messages")

    # the dmesg file is from serial console
    oops = `#{grep} -a -F -f #{KTEST_USER_GENERATED_DIR}/printk-error-messages #{kmsg_file} |
      grep -a -v -E -f #{LKP_SRC_ETC}/oops-pattern |
      grep -a -v -F -f #{LKP_SRC_ETC}/kmsg-denylist.raw;
      grep "Kernel tests: Boot OK" #{kmsg_file};`
    oops += `grep -a -E -f #{LKP_SRC_ETC}/ext4-crit-pattern #{kmsg_file}` if kmsg.index 'EXT4-fs ('
    oops += `grep -a -E -f #{LKP_SRC_ETC}/xfs-alert-pattern #{kmsg_file}` if kmsg.index 'XFS ('
    oops += `grep -a -E -f #{LKP_SRC_ETC}/btrfs-crit-pattern #{kmsg_file}` if kmsg.index 'btrfs: '
  end
  oops
end

def common_error_id(line)
  line.chomp
      .gsub(/\b[3-9]\.[0-9]+[-a-z0-9.]+/, '#') # linux version: 3.17.0-next-20141008-g099669ed
      .gsub(/\b[1-9][0-9]-[A-Z][a-z]+-[0-9]{4}\b/, '#') # Date: 28-Dec-2013
      .gsub(/\b0x[0-9a-f]+\b/, '#') # hex number
      .gsub(/\b[a-f0-9]{40}\b/, '#') # SHA-1
      .gsub(/\b[0-9][0-9.]*/, '#') # number
      .gsub(/#x\b/, '0x')
      .gsub(/[\\"$]/, '~')
      .gsub(/[ \t]/, ' ')
      .gsub(/\ \ +/, ' ')
      .gsub(/([^a-zA-Z0-9])\ /, '\1')
      .gsub(/\ ([^a-zA-Z])/, '\1')
      .remove(/^\ /)
      .gsub(/\  _/, '_')
      .tr(' ', '_')
      .remove(/[-_.,;:#!*\[(]+$/)
end

# # <4>[  256.557393] [ INFO: possible circular locking dependency detected ]
#  INFO_possible_circular_locking_dependency_detected: 1

def oops_to_bisect_pattern(line)
  words = line.split
  return '' if words.empty?
  return line if words.size == 1

  patterns = []
  words.each do |w|
    case w
    when /([a-zA-Z0-9_]+)\.(isra|constprop|part)\.[0-9]+\+0x/
      patterns << $1
      break
    when /([a-zA-Z0-9_]+\+0x)/, /([a-zA-Z0-9_]+=)/
      patterns << $1
      break
    when /^([a-zA-Z\/._-]*):[0-9]/
      patterns << "#{$1}:.*"
    when /[^a-zA-Z\/:.()!_-]/
      patterns << '.*' if patterns[-1] != '.*'
    else
      patterns << w
    end
  end
  patterns.shift while patterns[0] == '.*'
  patterns.pop   if patterns[-1] == '.*'
  patterns.join(' ')
end

def analyze_error_id(line)
  line = preprocess_line(line)

  case line
  when /(INFO: rcu[_a-z]* self-detected stall on CPU)/,
       /(INFO: rcu[_a-z]* detected stalls on CPUs\/tasks:)/,
       /(related general protection fault:)/,
       /(BUG: using __this_cpu_read\(\) in preemptible)/,
       /(BUG: unable to handle kernel)/,
       /(BUG: unable to handle kernel) NULL pointer dereference/,
       /(BUG: unable to handle kernel) paging request/,
       /(BUG: workqueue leaked lock or atomic:)/,
       /(BUG: scheduling while atomic:)/,
       /(BUG: Bad page map in process)/,
       /(BUG: Bad page state in process)/,
       /(BUG: Bad page cache in process)/,
       /(BUG: soft lockup - CPU#\d+ stuck for \d+s!.*)/,
       /(BUG: spinlock .* on CPU#\d+)/,
       /(Out of memory: Kill process) \d+ \(/,
       # old format: "[  122.209638 ] ??? Writer stall state 8 g62150 c62149 f0x2"
       # new format: "[  122.209638 ] ??? Writer stall state RTWS_STUTTER(8) g62150 c62149 f0x2"
       /(Writer stall state \w*).+ g\d+ c\d+ f/,
       /(BUG: workqueue lockup - pool)/,
       /(rcu_sched kthread starved) for \d+ jiffies/,
       /(Could not create tracefs)/,
       /(used greatest stack depth:)/,
       /([A-Z]+[ a-zA-Z]*): [a-f0-9]{4} \[#[0-9]+\] /,
       # [  406.307645] BUG: KASAN: slab-out-of-bounds in kfd_create_crat_image_virtual+0x129d/0x12fd
       /(BUG: KASAN: [a-z\-_ ]+ in [a-z_]+)\+/,
       # [   50.574901] BUG: KFENCE: out-of-bounds read in test_out_of_bounds_read+0x182/0x328
       /(BUG: KFENCE: [a-z\-_ ]+ in [a-z_]+)\+/,
       /(cpu clock throttled)/
    line = $1
    bug_to_bisect = $1
  when /(BUG: ).* (still has locks held)/,
       /(INFO: task ).* (blocked for more than \d+ seconds)/
    line = $1 + $2
    bug_to_bisect = $2
  when /WARNING:.* at .* ([a-zA-Z.0-9_]+\+0x)/
    bug_to_bisect = "WARNING:.* at .* #{$1.sub(/\.(isra|constprop|part)\.[0-9]+\+0x/, '')}"
    line =~ /(at .*)/
    line = "WARNING: #{$1}"
  when /(Kernel panic - not syncing: No working init found.)  Try passing init= option to kernel. /,
       /(Kernel panic - not syncing: No init found.)  Try passing init= option to kernel. /
    line = $1
    bug_to_bisect = line
  when /(BUG: key )[0-9a-f]+ (not in .data)/
    line = $1 + $2
    bug_to_bisect = "#{$1}.* #{$2}"
  when /(UBSAN: .+)/
    # UBSAN: Undefined behaviour in ../include/linux/bitops.h:110:33
    # UBSAN: shift-out-of-bounds in drivers/of/unittest.c:1893:36
    line = $1
    bug_to_bisect = oops_to_bisect_pattern line
  when /(BUG: using smp_processor_id\(\) in preemptible)/
    line = $1
    bug_to_bisect = oops_to_bisect_pattern line
  # printk(KERN_ERR "BUG: Dentry %p{i=%lx,n=%pd} still in use (%d) [unmount of %s %s]\n"
  when /(BUG: Dentry ).* (still in use) .* \[unmount of /
    line = $1 + $2
    bug_to_bisect = "#{$1}.* #{$2}"
  when /^backtrace:([a-zA-Z0-9_]+)/,
       /^calltrace:([a-zA-Z0-9_]+)/
    bug_to_bisect = "#{$1}+0x"
  when /Corrupted low memory at/
    # [   61.268659] Corrupted low memory at ffff880000007b08 (7b08 phys) = 27200c000000000
    bug_to_bisect = oops_to_bisect_pattern line
    line = line.sub(/\b[0-9a-f]+\b phys/, '# phys').sub(/= \b[0-9a-f]+\b/, '= #')
  when /kobject \(([0-9a-f]+|\(_*ptrval_*\))\): tried to init an initialized object/
    # [  512.848747] kobject (ca296866): tried to init an initialized object, something is seriously wrong.
    # [   50.433242] kobject ((ptrval)): tried to init an initialized object, something is seriously wrong.
    # [   36.605689] kobject ((____ptrval____)): tried to init an initialized object, something is seriously wrong.
    bug_to_bisect = oops_to_bisect_pattern line
    line = line.sub(/kobject \(([0-9a-f]+|\(_*ptrval_*\))\)/, 'kobject (#)')
  when /BUG: Bad rss-counter state mm:([0-9a-f]+|\(_*ptrval_*\)) /
    # [   70.951419 ] BUG: Bad rss-counter state mm:(____ptrval____) idx:1 val:4
    # [ 2841.215571 ] BUG: Bad rss-counter state mm:000000000fb13173 idx:1 val:-1
    # [   11.380524 ] BUG: Bad rss-counter state mm:(ptrval) idx:1 val:1
    # [   80.051123] BUG: Bad rss-counter state mm:0000000002d98df7 type:MM_ANONPAGES val:512
    # [   23.093962] BUG: Bad rss-counter state mm:(____ptrval____) type:MM_ANONPAGES val:-512
    bug_to_bisect = oops_to_bisect_pattern line
    line = line.sub(/BUG: Bad rss-counter state mm:([0-9a-f]+|\(_*ptrval_*\)) /, 'BUG: Bad rss-counter state mm:# ')
  when /Bad pagetable: [0-9a-f]+ \[#/
    # [   29.493015 ] Bad pagetable: 000f [#1] PTI
    # [    9.167214 ] Bad pagetable: 001d [#1] PTI
    # [    9.170529 ] Bad pagetable: 0009 [#2] PTI
    bug_to_bisect = oops_to_bisect_pattern line
    line = line.sub(/Bad pagetable: [0-9a-f]+ \[#/, 'Bad pagetable: # [#')
  when /(INFO: Slab 0x\(____ptrval____\) objects=.*fp=0x).* (flags=.*)/
    # [   16.160017 ] INFO: Slab 0x(____ptrval____) objects=23 used=23 fp=0x          (null) flags=0x10201
    # [   12.344185 ] INFO: Slab 0x(____ptrval____) objects=22 used=11 fp=0x(____ptrval____) flags=0x10201
    bug_to_bisect = oops_to_bisect_pattern line
    line = "#{$1}(#) #{$2}"
  when /^[0-9a-z]+>\] (.+)/
    # [   13.708945 ] [<0000000013155f90>] usb_hcd_irq
    line = $1
    bug_to_bisect = oops_to_bisect_pattern line
  when /(.*) \]---(.*)/
    # [    0.049111 ][    T0 ] ---[ end Kernel panic - not syncing: Fatal exception ]---
    line = "#{$1}#{$2}"
    bug_to_bisect = oops_to_bisect_pattern line
  when /segfault at .* ip .* sp .* error/
    # [ 2062.833046] pmbench[5394]: segfault at b ip 00007f568fec1ca6 sp 00007f54c1bf9d80 error 4 in libc-2.28.so[7f568fea8000+148000]
    # [  834.411251 ] init[1]: segfault at ffffffffff600400 ip ffffffffff600400 sp 00007fff59f7caa8 error 15
    line = 'segfault at ip sp error'
    bug_to_bisect = oops_to_bisect_pattern line
  else
    bug_to_bisect = oops_to_bisect_pattern line
  end

  error_id = generate_error_id(line)

  [error_id, bug_to_bisect]
end

def preprocess_line(line)
  line = line.sub(/^(kern  |user  |daemon):......: /, '')

  # remove caller information from CONFIG_PRINTK_CALLER
  # [   55.954373][    T1] UBI error: cannot initialize UBI, error -1 => [   55.954373] UBI error: cannot initialize UBI, error -1
  line.sub!(/\[ {0,4}[A-Z][0-9]{1,5}\] /, ' ')

  line.sub!(/^[^a-zA-Z]+/, '')
  # line.sub!(/^\[ *[0-9]{1,6}\.[0-9]{6}\] )/, '') # the above pattern includes this one
  line
end

def generate_error_id(line)
  error_id = line

  error_id.remove!(/\ \]$/) # [ INFO: possible recursive locking detected ]
  error_id.remove!(/\/c\/kernel-tests\/src\/[^\/]+\//)
  error_id.remove!(/\/c\/(wfg|yliu)\/[^\/]+\//)
  error_id.remove!(/\/lkp\/[^\/]+\/linux[0-9]*\//)
  error_id.remove!(/\/kernel-tests\/linux[0-9]*\//)
  error_id.remove!(/\.(isra|constprop|part)\.[0-9]+/)

  # [   31.694592] ADFS-fs error (device nbd10): adfs_fill_super: unable to read superblock
  # [   33.147854] block nbd15: Attempted send on closed socket
  # /c/linux-next% git grep -w 'register_blkdev' | grep -o '".*"'
  error_id.gsub!(/\b(bcache|blkext|btt|dasd|drbd|fd|hd|jsfd|lloop|loop|md|mdp|mmc|nbd|nd_blk|nfhd|nullb|nvme|pmem|ramdisk|scm|sd|simdisk|sr|ubd|ubiblock|virtblk|xsysace|zram)\d+/, '\1#')

  error_id.gsub! LINUX_DEVICE_NAMES_RE, '\1#'

  error_id.gsub!(/\b[0-9a-f]{8}\b/, '#')
  error_id.gsub!(/\b[0-9a-f]{16}\b/, '#')
  error_id.gsub!(/(=)[0-9a-f]+\b/, '\1#')
  error_id.remove!(/[+\/]0x[0-9a-f]+\b/)
  error_id.remove!(/[+\/][0-9a-f]+\b/)

  # [   14.476643][    C0] BUG kmalloc-512 (Tainted: G S      W       T ): Right Redzone overwritten
  # [  264.548980][    C1] BUG kmalloc-rnd-02-96 (Tainted: G        W       TN): Freechain corrupt
  error_id.remove!(/ \(Tainted:.+\)/)

  error_id = common_error_id(error_id)

  error_id.gsub!(/([a-z]:)[0-9]+\b/, '\1') # WARNING: at arch/x86/kernel/cpu/perf_event.c:1077 x86_pmu_start+0xaa/0x110()
  error_id.remove!(/#:\[<#>\]\[<#>\]/) # RIP: 0010:[<ffffffff91906d8d>]  [<ffffffff91906d8d>] validate_chain+0xed/0xe80
  error_id.gsub!(/RIP:#:/, 'RIP:')       # RIP: 0010:__might_sleep+0x72/0x80
  error_id.gsub!(/[^\/a-zA-Z0-9_]\w[0-9]+\W/, '#') # dmesg.BUG:soft_lockup-CPU##stuck_for#s![trinity-c0:#]
  error_id.gsub!(/\W\w[0-9]+[^\/a-zA-Z0-9_]/, '#') # dmesg.BUG:soft_lockup-CPU##stuck_for#s![kworker/u258:#:#]

  error_id
end

def get_crash_stats(dmesg_file)
  if dmesg_file =~ /\.xz$/
    `xz -d -k #{dmesg_file}`
    uncompressed_dmesg = dmesg_file.remove(/\.xz$/)
    dmesg_file = uncompressed_dmesg
  end

  boot_error_ids = `#{LKP::Programs.find_parser('dmesg')} #{dmesg_file}`

  oops_map = {}
  id = ''
  new_error_id = false
  boot_error_ids.each_line do |line|
    line.chomp!
    if line =~ /^# /
      new_error_id = true
      next
    end

    if new_error_id
      # WARNING:at_kernel/locking/lockdep.c:#lock_release: 1
      id = line.split(': ')[0..-2].join(': ')
      new_error_id = false
      next
    end

    next unless line =~ /^message:/

    # message:WARNING:at_kernel/locking/lockdep.c:#lock_release: [   11.858566 ] WARNING: CPU: 0 PID: 11 at kernel/locking/lockdep.c:3536 lock_release+0x179/0x3b7
    #
    oops_map[id] = line.split(': ')[1..-1].join(': ')
  end

  FileUtils.rm uncompressed_dmesg if uncompressed_dmesg

  oops_map
end

def get_content(dmesg_file)
  if dmesg_file =~ /\.xz$/
    `xz -d -k #{dmesg_file} --stdout`
  else
    File.read(dmesg_file)
  end
end

CALLTRACE_LIMIT_LEN = 100
DECODE_FLAG = 'Code starting with the faulting instruction'.freeze
def get_crash_calltraces(dmesg_file)
  dmesg_content = get_content(dmesg_file)

  calltraces = []
  index = 0
  line_count = 0
  in_calltrace = false
  end_calltrace = false

  in_decode = false
  end_decode = false
  decode_stacktrace = dmesg_content.include?(DECODE_FLAG)
  dmesg_content.remove!(/kbuild\/src\/[^\/]+\//)

  dmesg_content.each_line do |line|
    if line =~ /---\[ cut here | BUG: | WARNING: | INFO: | UBSAN: | kernel BUG at /
      in_calltrace = true
      if end_calltrace
        index += 1
        end_calltrace = false
      end
      in_decode = false
      end_decode = false

      calltraces[index] ||= ''
      calltraces[index] << line
      line_count = 1
    elsif line.index('---[ end trace ') && in_calltrace
      in_calltrace = false
      end_calltrace = true
      calltraces[index] << line
    elsif in_calltrace
      calltraces[index] << line
      line_count += 1
      if line_count > CALLTRACE_LIMIT_LEN
        in_calltrace = false
        end_calltrace = true
      end
    elsif !end_decode && end_calltrace && decode_stacktrace
      if !in_decode
        line_count += 1
        calltraces[index] << line
        in_decode = true if line.index(DECODE_FLAG)
        end_decode = true if line_count > CALLTRACE_LIMIT_LEN * 1.5
      elsif line !~ /^(===|  ( [0-9a-f]|[0-9a-f]{2}):| +\.\.\.)/
        in_decode = false
        end_decode = true
      else
        calltraces[index] << line
      end
    end
  end

  calltraces
end

def put_dmesg_stamps(error_stamps)
  puts
  error_stamps.each do |error_id, timestamp|
    puts "timestamp:#{error_id}: #{timestamp}"
  end
end

# when lkdtm is complete run, ignore dmesg
def ignore_lkdtm_dmesg?(result_root)
  last_state = "#{result_root}/last_state"
  return false unless last_state =~ /\/kernel-selftests\/lkdtm/
  return true unless File.exist?(last_state)

  File.foreach(last_state).grep(/^is_incomplete_run: 1/).empty?
end

def stat_unittest(lines)
  stats = LKP::Stats.new

  test_along_with_function_tracer = nil

  lines.each do |line|
    case line
    when /### dt-test ### (pass|fail) (.+)/i
      # ### dt-test ### pass of_unittest_match_node():1497
      stats.add("of-unittest.#{$2}", $1, overwrite: true)
    when /Running tests again, along with the function tracer/
      test_along_with_function_tracer = 'function tracer'
    when /Testing (.+): OK/
      # Testing event system initcall: OK
      test_case = $1
      test_case = "#{test_along_with_function_tracer}.#{test_case}" if test_along_with_function_tracer
      stats.add(test_case, :pass)

      test_along_with_function_tracer = nil if line =~ /Testing ftrace filter: OK/
    when /Testing (.+): (PASSED)/
      # Testing event system initcall: OK
      stats.add($1, :pass)
    when /(\w+):\s.+\d+ tests passed/
      # test_hexdump: all 1184 tests passed
      # IDA: 147357 of 147357 tests passed
      stats.add($1.downcase, :pass)
    when /test_meminit: all \d+ tests in (test_.+) (passed)/
      # test_meminit: all 11 tests in test_pages passed
      stats.add("test_meminit.#{$1}", :pass)
    when /Kernel tests: Boot OK|run-job \/lkp/
      break
    end
  end

  stats.dump('ok' => :pass)
end

# check possibly misplaced serial log
def verify_serial_log(dmesg_lines)
  return unless $PROGRAM_NAME =~ /dmesg/
  return if RESULT_ROOT.nil? || RESULT_ROOT.empty?

  dmesg_lines.grep(/RESULT_ROOT=/) do |line|
    next if line =~ /(^|[0-9]\] )kexec -l | --initrd=| --append=|"$/
    next unless line =~ / RESULT_ROOT=([A-Za-z0-9.,;_\/+%:@=-]+) /

    rt = $1
    next unless Dir.exist? rt # serial console is often not reliable

    log_error "RESULT_ROOT mismatch in dmesg: #{RESULT_ROOT} #{rt}" if rt != RESULT_ROOT
  end
end
