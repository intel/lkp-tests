require 'spec_helper'
require "#{LKP_SRC}/lib/changed_stat"

describe 'LKP::ChangedStat' do
  after do
    LKP::ChangedStat.singleton_class.cache_store(:project_git).clear
  end

  describe '.project_git' do
    it 'caches the Git::Base object per (project, remote), calling Git.open only once' do
      git = instance_double(Git::Base)
      allow(Git).to receive(:open).with(project: 'linux', remote: 'linus').and_return(git)

      first = LKP::ChangedStat.project_git('linux', 'linus')
      second = LKP::ChangedStat.project_git('linux', 'linus')

      expect(first).to be(git)
      expect(second).to be(git)
      expect(Git).to have_received(:open).once
    end

    it 'opens a distinct object for a different (project, remote) key' do
      git_a = instance_double(Git::Base)
      git_b = instance_double(Git::Base)
      allow(Git).to receive(:open).with(project: 'linux', remote: 'linus').and_return(git_a)
      allow(Git).to receive(:open).with(project: 'dpdk', remote: nil).and_return(git_b)

      expect(LKP::ChangedStat.project_git('linux', 'linus')).to be(git_a)
      expect(LKP::ChangedStat.project_git('dpdk', nil)).to be(git_b)
    end
  end

  describe '.refresh_project_git' do
    it 'discards the cached object and returns a freshly opened one for the same key' do
      stale_git = instance_double(Git::Base)
      fresh_git = instance_double(Git::Base)
      allow(Git).to receive(:open).with(project: 'linux', remote: 'linus').and_return(stale_git, fresh_git)

      cached = LKP::ChangedStat.project_git('linux', 'linus')
      expect(cached).to be(stale_git)

      refreshed = LKP::ChangedStat.refresh_project_git('linux', 'linus')
      expect(refreshed).to be(fresh_git)

      # the refreshed object is now the one served from cache
      expect(LKP::ChangedStat.project_git('linux', 'linus')).to be(fresh_git)
    end
  end
end
