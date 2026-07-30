require 'spec_helper'
require "#{LKP_SRC}/lib/result"

describe ResultPath do
  describe '#parse_result_root' do
    context 'handles default path' do
      context 'when valid result root' do
        it 'succesds' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9/0f57d86787d8b1076ea8f9cbdddda2a46d534a27/2")).to be true
          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9/0f57d86787d8b1076ea8f9cbdddda2a46d534a27/")).to be true
          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9/0f57d86787d8b1076ea8f9cbdddda2a46d534a27")).to be true
          expect(result_path['testcase']).to eq 'aim7'
          expect(result_path['path_params']).to eq 'performance-2000-fork_test'
          expect(result_path['tbox_group']).to eq 'brickland3'
          expect(result_path['rootfs']).to eq 'debian-x86_64-2015-02-07.cgz'
          expect(result_path['kconfig']).to eq 'x86_64-rhel'
          expect(result_path['compiler']).to eq 'gcc-4.9'
          expect(result_path['commit']).to eq '0f57d86787d8b1076ea8f9cbdddda2a46d534a27'
        end
      end

      context 'when invalid result root' do
        it 'fails' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9/0f57d86787d8b1076ea8f9cbdddda2a46d534a2")).to be false
          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9/")).to be false
          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9")).to be false
        end
      end
    end

    context 'handles kvm:default path' do
      context 'when valid result root' do
        it 'succesds' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/kvm:vm-scalability/performance-300s-lru-file-mmap-read-rand/lkp-skl-2sp7/debian-x86_64-20191114.cgz/x86_64-rhel-7.6/gcc-7/7472c4028e2357202949f99ad94c5a5a34f95666/0")).to be true
          expect(result_path['testcase']).to eq 'kvm:vm-scalability'
          expect(result_path['path_params']).to eq 'performance-300s-lru-file-mmap-read-rand'
          expect(result_path['tbox_group']).to eq 'lkp-skl-2sp7'
          expect(result_path['rootfs']).to eq 'debian-x86_64-20191114.cgz'
          expect(result_path['kconfig']).to eq 'x86_64-rhel-7.6'
          expect(result_path['compiler']).to eq 'gcc-7'
          expect(result_path['commit']).to eq '7472c4028e2357202949f99ad94c5a5a34f95666'
        end
      end

      context 'when invalid result root' do
        it 'fails' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/kvm:vm-scalability/lkp-skl-2sp7/debian-x86_64-20191114.cgz/x86_64-rhel-7.6/gcc-7/7472c4028e2357202949f99ad94c5a5a34f95666/")).to be false
          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/kvm:vm-scalability/performance-300s-lru-file-mmap-read-rand/lkp-skl-2sp7/debian-x86_64-20191114.cgz/x86_64-rhel-7.6/gcc-7/747")).to be false
        end
      end
    end

    context 'handles hwinfo path' do
      context 'when valid result root' do
        it 'succesds' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/hwinfo/lkp-bdw-ep6/1")).to be true
          expect(result_path['testcase']).to eq 'hwinfo'
          expect(result_path['tbox_group']).to eq 'lkp-bdw-ep6'
        end
      end

      context 'when invalid result root' do
        it 'fails' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/hwinfo")).to be false
        end
      end
    end

    context 'handles deploy-clang path' do
      context 'when valid result root' do
        it 'succesds' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/deploy-clang/debian-x86_64-20191114.cgz/073dbaae39724ea860b5957fe47ecc1c2a84b197/0")).to be true
          expect(result_path['testcase']).to eq 'deploy-clang'
          expect(result_path['rootfs']).to eq 'debian-x86_64-20191114.cgz'
          expect(result_path['llvm_project_commit']).to eq '073dbaae39724ea860b5957fe47ecc1c2a84b197'
        end
      end

      context 'when invalid result root' do
        it 'fails' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/deploy-clang/65b21282c710afe9c275778820c6e3c1")).to be false
        end
      end
    end

    context 'handles kvm-kernel-boot-test path' do
      context 'when valid result root' do
        it 'succesds' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/kvm-kernel-boot-test/lkp-csl-2sp7/x86_64-rhel-7.6/0ecfebd2b52404ae0c54a878c872bb93363ada36/x86_64-softmmu/fb2246882a2c8d7f084ebe0617e97ac78467d156/2595646791c319cadfdbf271563aac97d0843dc7/0/")).to be true
          expect(result_path['testcase']).to eq 'kvm-kernel-boot-test'
          expect(result_path['tbox_group']).to eq 'lkp-csl-2sp7'
          expect(result_path['kconfig']).to eq 'x86_64-rhel-7.6'
          expect(result_path['commit']).to eq '0ecfebd2b52404ae0c54a878c872bb93363ada36'
          expect(result_path['qemu_config']).to eq 'x86_64-softmmu'
          expect(result_path['qemu_commit']).to eq 'fb2246882a2c8d7f084ebe0617e97ac78467d156'
          expect(result_path['linux_commit']).to eq '2595646791c319cadfdbf271563aac97d0843dc7'
        end
      end

      context 'when invalid result root' do
        it 'fails' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/kvm-kernel-boot-test/lkp-csl-2sp7/x86_64-rhel-7.6/")).to be false
        end
      end
    end

    context 'handles health-stats path' do
      context 'when valid result root' do
        it 'succesds' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/health-stats/__date_+%F_-d_yesterday_/0")).to be true
          expect(result_path['testcase']).to eq 'health-stats'
          expect(result_path['path_params']).to eq '__date_+%F_-d_yesterday_'
        end
      end

      context 'when invalid result root' do
        it 'fails' do
          result_path = described_class.new

          expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/health-stats")).to be false
        end
      end
    end

    context 'when set is_local_run to true' do
      it 'do not check commit id' do
        result_path = described_class.new

        # The commit name is kernel version in local run.
        expect(result_path.parse_result_root("#{RESULT_ROOT_DIR}/will-it-scale/process-100%-brk1/shao2-debian/debian/x86_64-rhel-7.6/gcc-7/4.19.0-4-amd64/0", is_local_run: true)).to be true
        expect(result_path['testcase']).to eq 'will-it-scale'
        expect(result_path['path_params']).to eq 'process-100%-brk1'
        expect(result_path['tbox_group']).to eq 'shao2-debian'
        expect(result_path['rootfs']).to eq 'debian'
        expect(result_path['kconfig']).to eq 'x86_64-rhel-7.6'
        expect(result_path['compiler']).to eq 'gcc-7'
        expect(result_path['commit']).to eq '4.19.0-4-amd64'
      end
    end
  end

  describe '#parse_test_desc' do
    it 'handles test desc with dedault param' do
      result_path = described_class.new
      result_path['testcase'] = 'xfstests'

      test_desc = result_path.parse_test_desc('xfstests/4HDD-xfs-xfs-group17/vm-snb/e93c9c99a629c61837d5a7fc2120cd2b6c70dbdd')
      expect(test_desc['path_params']).to eq '4HDD-xfs-xfs-group17'
      expect(test_desc['tbox_group']).to eq 'vm-snb'
      expect(result_path['commit']).to be_nil
    end

    it 'handles test desc with dim_not_a_param=false' do
      result_path = described_class.new
      result_path['testcase'] = 'xfstests'

      test_desc = result_path.parse_test_desc('xfstests/4HDD-xfs-xfs-group17/vm-snb/e93c9c99a629c61837d5a7fc2120cd2b6c70dbdd', dim_not_a_param: false)
      expect(test_desc['path_params']).to eq '4HDD-xfs-xfs-group17'
      expect(test_desc['tbox_group']).to eq 'vm-snb'
      expect(test_desc['commit']).to eq 'e93c9c99a629c61837d5a7fc2120cd2b6c70dbdd'
    end
  end

  describe '#each_commit' do
    it 'handles default path' do
      result_path = described_class.new

      result_path.parse_result_root("#{RESULT_ROOT_DIR}/aim7/performance-2000-fork_test/brickland3/debian-x86_64-2015-02-07.cgz/x86_64-rhel/gcc-4.9/0f57d86787d8b1076ea8f9cbdddda2a46d534a27/2")

      result_path.each_commit do |project, commit_axis|
        expect(project).to eq 'linux'
        expect(commit_axis).to eq 'commit'
      end
    end
  end

  describe '.with_release_tag' do
    before do
      stub_const 'GIT_WORK_TREE', File.join(git_root_dir, 'linux')
      stub_const 'GIT_DIR', "#{GIT_WORK_TREE}/.git"
      stub_const 'GIT', "git --work-tree=#{GIT_WORK_TREE} --git-dir=#{GIT_DIR}"
    end

    # commit 64291f7db5bd8150a74ad2036f1037e6a0428df2 is tagged v4.2
    it 'substitutes the commit segment with its Linus release tag when found' do
      result_root = '/result/testcase/tbox/rootfs/kconfig/compiler/64291f7db5bd8150a74ad2036f1037e6a0428df2/0'
      expect(described_class.with_release_tag(result_root))
        .to eq '/result/testcase/tbox/rootfs/kconfig/compiler/v4.2/0'
    end

    # regression test: a result_root whose path has one extra segment past
    # the commit (e.g. a raw file path instead of the result-root
    # directory) makes this extract a run number like "0" instead of a
    # real commit. That used to crash with a Bash::BashCallError from the
    # underlying `git log ... "0"` call; it must now fail soft and return
    # the path unchanged, same as the original bash implementation did.
    it 'returns the path unchanged, without raising, when the commit segment is not a real ref' do
      result_root = '/result/testcase/tbox/rootfs/kconfig/compiler/0/1'
      expect { described_class.with_release_tag(result_root) }.not_to raise_error
      expect(described_class.with_release_tag(result_root)).to eq result_root
    end

    it 'returns the path unchanged for paths outside /result/' do
      expect(described_class.with_release_tag('/other/path')).to eq '/other/path'
    end
  end
end
