#!/usr/bin/env ruby

############################################
#                                          #
# Favor to add new functions to Git class! #
#                                          #
############################################

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'set'
require 'time'
require "#{LKP_SRC}/lib/assert"
require "#{LKP_SRC}/lib/cache"
require "#{LKP_SRC}/lib/constant"
require "#{LKP_SRC}/lib/git"
require "#{LKP_SRC}/lib/lkp_path"
require "#{LKP_SRC}/lib/run_env"
require "#{LKP_SRC}/lib/yaml"

GIT_WORK_TREE ||= ENV['GIT_WORK_TREE'] || ENV['LKP_GIT_WORK_TREE'] || "#{GIT_ROOT_DIR}/linux"
GIT_DIR ||= ENV['GIT_DIR'] || "#{GIT_WORK_TREE}/.git"
GIT ||= "git --work-tree=#{GIT_WORK_TREE} --git-dir=#{GIT_DIR}".freeze

def __git_committer_name(commit)
  `#{GIT} log -n1 --pretty=format:'%cn' "#{commit}"`.chomp
end

def git_committer_name(commit)
  $__committer_name_cache ||= {}
  $__committer_name_cache[commit] ||= __git_committer_name(commit)
  $__committer_name_cache[commit]
end

def __git_parents(commit)
  `#{GIT} rev-list --parents -n1 "#{commit}"`.chomp.split[1..]
end

def git_parents(commit)
  $__parents_cache ||= {}
  $__parents_cache[commit] ||= __git_parents(commit)
  $__parents_cache[commit]
end

def __git_patchid(commit)
  `#{GIT} show "#{commit}" 2>/dev/null | git patch-id --stable | awk '{ print $1 }'`.chomp
end

def git_patchid(commit)
  $__patchid_cache ||= {}
  patch_id = __git_patchid(commit)
  $__patchid_cache[commit] ||= patch_id unless patch_id.empty?
  $__patchid_cache[commit]
end

def linus_commit?(commit)
  git_committer_name(commit) == 'Linus Torvalds'
end

def git_commit(commit)
  return commit if sha1_40?(commit)

  $__git_commit_cache ||= {}
  return $__git_commit_cache[commit] if $__git_commit_cache.include?(commit)

  sha1_commit = `#{GIT} rev-list -n1 "#{commit}"`.chomp
  $__git_commit_cache[commit] = sha1_commit unless sha1_commit.empty?
  sha1_commit
end

def __commit_tag(commit)
  tags = `#{GIT} tag --points-at "#{commit}"`.split
  tags.each do |tag|
    return tag if linus_tags.include? tag
  end
  tags[0]
end

def commit_tag(commit)
  $__commit_tag_cache ||= {}
  return $__commit_tag_cache[commit] if $__commit_tag_cache.include?(commit)

  $__commit_tag_cache[commit] = __commit_tag(commit)
end

def linus_release_tag(commit)
  return unless linus_commit?(commit)

  tag = commit_tag(commit)
  case tag
  when /^v[345]\.\d+(-rc\d+)?$/, /^v2\.\d+\.\d+(-rc\d)?$/
    tag
  end
end

# if commit has a version tag, return it directly;
# otherwise checkout commit and get latest version from Makefile.
def __last_linus_release_tag(commit)
  tag = linus_release_tag commit
  return [tag, true] if tag =~ /^v.*/

  version = patch_level = sub_level = rc = nil

  `#{GIT} show "#{commit}:Makefile"`.each_line do |line|
    case line
    when /^VERSION *= *(\d+)/
      version = $1.to_i
    when /^PATCHLEVEL *= *(\d+)/
      patch_level = $1.to_i
    when /^SUBLEVEL *= *(\d+)/
      sub_level = $1.to_i
    when /^EXTRAVERSION *= *-rc(\d+)/
      rc = $1.to_i
    when /^NAME *= */
      break
    else
      next
    end
  end

  if version && version >= 3
    tag = "v#{version}.#{patch_level}"
  elsif version == 2
    tag = "v2.#{patch_level}.#{sub_level}"
  else
    log_warn "Not a kernel tree? check #{GIT_WORK_TREE}"
    log_warn caller.join "\n"
    return
  end

  tag += "-rc#{rc}" if rc&.positive?
  [tag, false]
end

def last_linus_release_tag(commit)
  $__last_linus_tag_cache ||= {}
  $__last_linus_tag_cache[commit] ||= __last_linus_release_tag(commit)
  $__last_linus_tag_cache[commit]
end

def compare_version(aa, bb)
  aa.names.each do |name|
    aaa = aa[name]
    bbb = bb[name]
    next if aaa == bbb

    direction = if name =~ /prerelease/
                  -1
                else
                  1
                end
    if aaa && bbb
      unless name =~ /str|name/
        aaa = aaa.to_i
        bbb = bbb.to_i
      end
      return aaa <=> bbb
    elsif aaa && !bbb
      return direction
    elsif !aaa && bbb
      return -direction
    end
  end
  0
end

def sort_tags(pattern, tags)
  tags.sort do |a, b|
    aa = pattern.match a
    bb = pattern.match b
    -compare_version(aa, bb)
  end
end

def get_tags(pattern, _committer)
  tags = []
  `#{GIT} tag -l`.each_line do |tag|
    tag.chomp!
    next unless pattern.match(tag)

    # disabled: too slow and lots of git lead to OOM
    # next unless committer == nil or committer == git_committer_name(tag)
    tags << tag
  end
  tags
end

# => ["v3.11-rc6", "v3.11-rc5", "v3.11-rc4", "v3.11-rc3", "v3.11-rc2", "v3.11-rc1",
#     "v3.10", "v3.10-rc7", "v3.10-rc6", ..., "v2.6.12-rc3", "v2.6.12-rc2", "v2.6.11"]
def __linus_tags
  $remotes ||= load_remotes
  pattern = Regexp.new "^#{Array($remotes['linus']['release_tag_pattern']).join('$|^')}$"
  tags = get_tags(pattern, $remotes['linus']['release_tag_committer'])
  tags = sort_tags(pattern, tags)
  tags_order = {}
  tags.each_with_index do |tag, i|
    tags_order[tag] = -i
  end
  tags_order
end

def linus_tags
  $__linus_tags_cache ||= __linus_tags
  $__linus_tags_cache
end

def base_rc_tag(commit)
  commit += '~' if linus_commit?(commit)
  version, _is_exact_match = last_linus_release_tag commit
  version
end

def load_remotes
  remotes = {}
  files = Dir[LKP::Path.src('repo', '*', '*')]
  files.each do |file|
    remote = File.basename file
    next if remote == 'DEFAULTS'

    defaults = "#{File.dirname(file)}/DEFAULTS"
    repo_info = load_yaml_merge [defaults, file]

    project = File.basename(File.dirname(file))
    repo_info['project'] ||= project
    repo_info['suite'] ||= "#{project}-ci"
    repo_info['testcase'] ||= "#{project}-ci"

    repo_info['upstream'] = true if repo_info['project'] == remote

    if repo_info['upstream']
      repo_info['fetch_tags']         = true
      repo_info['git_am_branch']    ||= 'master'
      repo_info['maintained_files'] ||= '*'
    end

    log_warn "conflict repo name in different projects: #{remote}" if remotes[remote]

    remotes[remote] = repo_info
  end
  remotes
end

def git_committer(commit)
  `#{GIT} log -n1 --pretty=format:'%cn <%ce>' "#{commit}"`.chomp
end

def git_commit_author(commit)
  `#{GIT} log -n1 --pretty=format:'%an <%ae>' "#{commit}"`.chomp
end

def relative_commit_date(commit)
  `#{GIT} log -n1 --format=format:"%cr" "#{commit}"`.chomp
end

def git_commit_subject(commit)
  `#{GIT} log -1 --format=%s "#{commit}"`.chomp
end

def remote_exists?(remote)
  `#{GIT} remote` =~ /^#{remote}$/
end

def branch_exists?(branch)
  `#{GIT} branch --list -r "#{branch}"` != ''
end

def commit_exists?(commit)
  `#{GIT} rev-list -1 "#{commit}"` != ''
end

def merge_commit?(commit)
  git_parents(commit).many?
end

def __commit_name(commit)
  return commit unless commit =~ /^[a-f0-9]+$/ || commit =~ /^v\d\.\d+/

  name = commit[0..11]
  "#{name} #{git_commit_subject(commit)[0..59]}"
end

$__commit_name_cache = {}
def commit_name(commit)
  $__commit_name_cache[commit] ||= __commit_name(commit)
end

def sha1_40?(commit)
  commit =~ /^[\da-f]{40}$/
end
