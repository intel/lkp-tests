#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__, 2)

require "#{LKP_SRC}/lib/cache"
require "#{LKP_SRC}/lib/git/base"
require "#{LKP_SRC}/lib/git/object"

module Git
  class Base
    include Cacheable

    # a ref that isn't already a resolved 40-char sha (HEAD, a branch, a tag,
    # an abbreviated sha) can be re-pointed to a different commit between two
    # calls on the same instance, so only ever cache the already-immutable
    # sha form.
    cache_method :gcommit, cache_key_prefix_generator: lambda(&:object_id), skip_cache: ->(ref) { !Git.sha1_40?(ref) }
  end
end

module Git
  class Object
    class Commit
      include Cacheable

      cache_method :release_tag, cache_key_prefix_generator: lambda(&:to_s)
      cache_method :last_release_tag, cache_key_prefix_generator: lambda(&:to_s)
    end
  end
end
