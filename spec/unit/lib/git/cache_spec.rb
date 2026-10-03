require 'spec_helper'
require "#{LKP_SRC}/lib/git"
require "#{LKP_SRC}/lib/lkp_tmpdir"

describe 'Git::Base#gcommit caching' do
  def commit_file(content, message)
    File.write(File.join(@tmpdir.path, 'a'), content)
    Dir.chdir(@tmpdir.path) { `git add a && git commit -q -m #{message}` }
  end

  before do
    @tmpdir = LKP::TmpDir.new('git-cache-spec')
    Dir.chdir(@tmpdir.path) do
      `git init -q`
      `git config user.email test@example.com`
      `git config user.name Test`
    end
    commit_file('1', 'first')
  end

  after do
    @tmpdir.clean!
  end

  it 'does not return a stale sha for a moving ref (HEAD) after it advances on the same instance' do
    git = Git.open(working_dir: @tmpdir.path, project: 'cache-spec-test')
    first_sha = git.gcommit('HEAD').sha

    commit_file('2', 'second')

    expect(git.gcommit('HEAD').sha).not_to eq(first_sha)
  end

  it 'still caches repeated lookups of an already-resolved 40-char sha' do
    git = Git.open(working_dir: @tmpdir.path, project: 'cache-spec-test')
    sha = git.gcommit('HEAD').sha

    first = git.gcommit(sha)
    second = git.gcommit(sha)

    expect(second).to equal(first)
  end
end
