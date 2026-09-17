LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require 'ostruct'

module Cacheable
  def self.included(mod)
    class << mod; include ClassMethods; end
  end

  module ClassMethods
    def cache_store(_method_name)
      @cache_store ||= {}
    end

    def cache_options
      @cache_options ||= {}
    end

    #
    # cache_key_prefix_generator - customized key prefix generator, possible values
    #   default => share cache between all objects belong to same class
    #   ->(obj) {obj.class.to_s} => same effect as default
    #   ->(obj) {obj.to_s} => share cache between objects who has same to_s
    #   ->(obj) {obj.object_id} => do not share cache between objects
    #
    def cache_method(method_name, options = {})
      # credit to rails alias_method_chain
      alias_method "#{method_name}_without_cache", method_name

      kclass = self

      cache_options[method_name] = options

      # rli9 FIXME: not support &block
      # rli9 FIXME: better solution for generating key can refer to
      # https://github.com/seamusabshere/cache_method/blob/master/lib/cache_method.rb
      #
      # Explicit *args/**kwargs all the way down this module, not
      # ruby2_keywords: a caller can reopen Cacheable::ClassMethods to
      # add a different cache backend, and any such override of a
      # method in this forwarding chain must itself declare/forward
      # **kwargs (not rely on a ruby2_keywords-flagged Hash surviving
      # *args forwarding) -- an override that only takes *args, with no
      # **kwrest or keyword params, makes Ruby silently coerce a
      # keyword call's Hash into a positional argument instead of
      # raising a clear error, which then blows up as an
      # unrelated-looking ArgumentError ("wrong number of arguments")
      # several calls further down at the final obj.send to the raw,
      # keyword-only wrapped method. Confirmed live via exactly this
      # kind of stale, non-kwargs override elsewhere in the framework.
      define_method(method_name) do |*args, **kwargs|
        kclass.cache_fetch(self, method_name, *args, **kwargs)
      rescue StandardError => e
        # a cache-internal failure must not hide the underlying method's
        # result, but it also must not vanish silently (it used to, see
        # git history), so it can be diagnosed if it recurs
        warn "Cacheable: #{kclass}##{method_name} cache lookup failed (#{e.class}: #{e.message}), falling back to uncached call"
        send("#{method_name}_without_cache", *args, **kwargs)
      end
    end

    def cache_fetch(obj, method_name, *args, **kwargs)
      cache_store = cache_store(method_name)
      cache_key = cache_key(obj, method_name, *args, **kwargs)

      if cache_store.instance_of?(Hash)
        cache_fetch_hash(cache_store, cache_key, obj, method_name, *args, **kwargs)
      else
        cache_store.fetch cache_key do
          obj.send("#{method_name}_without_cache", *args, **kwargs)
        end
      end
    end

    def cache_fetch_hash(cache_store, cache_key, obj, method_name, *args, **kwargs)
      # rli9 FIXME the operation to hash is not thread safe
      if cache_store.key?(cache_key)
        cache = cache_store[cache_key]
        return cache.value unless cache_expired?(method_name, cache.timestamp)

        cache_store.delete(cache_key)
      end

      value = obj.send("#{method_name}_without_cache", *args, **kwargs)
      return if value.nil? && !cache_options[method_name][:cache_nil]

      cache_store[cache_key] = OpenStruct.new(value: value, timestamp: Time.now)
      cache_store[cache_key].value
    end

    def cache_expired?(method_name, timestamp)
      cache_expire = cache_options[method_name][:cache_expire]
      return false unless cache_expire

      (Time.now - timestamp).to_i > cache_expire
    end

    def cache_key(obj, method_name, *args, **kwargs)
      # rli9 FIXME: to understand performance impact of different hash key
      # cache_key = [self, method_name, args]
      key_parts = kwargs.empty? ? args : args + [kwargs]
      cache_key = "#{obj.instance_of?(Class) ? obj.to_s : obj.class.to_s}_#{method_name}_#{key_parts.join('_')}"

      cache_key_prefix_generator = cache_options[method_name][:cache_key_prefix_generator]
      cache_key = "#{cache_key_prefix_generator.call obj}_#{cache_key}" if cache_key_prefix_generator

      cache_key
    end
  end
end
