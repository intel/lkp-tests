require 'spec_helper'
require "#{LKP_SRC}/lib/cache"

describe 'Cacheable' do
  before do
    stub_const('CacheableFixture', Class.new do
      class << self
        include Cacheable

        attr_accessor :call_count

        def replicas(live: false)
          self.call_count += 1
          live ? "live-#{call_count}" : "static-#{call_count}"
        end
        cache_method :replicas
      end
    end)
    CacheableFixture.call_count = 0
  end

  describe '.cache_method' do
    it 'forwards a keyword argument through to the wrapped method' do
      expect(CacheableFixture.replicas(live: true)).to eq('live-1')
    end

    it 'still supports calling with no arguments' do
      expect(CacheableFixture.replicas).to eq('static-1')
    end

    it 'caches a repeated call with the same keyword argument instead of re-invoking the method' do
      first = CacheableFixture.replicas(live: true)
      second = CacheableFixture.replicas(live: true)

      expect(second).to eq(first)
      expect(CacheableFixture.call_count).to eq(1)
    end

    it 'does not conflate different keyword-argument values under one cache entry' do
      expect(CacheableFixture.replicas(live: true)).to eq('live-1')
      expect(CacheableFixture.replicas(live: false)).to eq('static-2')
      expect(CacheableFixture.call_count).to eq(2)
    end
  end

  describe '.cache_method with skip_cache' do
    before do
      stub_const('SkipCacheFixture', Class.new do
        class << self
          include Cacheable

          attr_accessor :call_count

          def resolve(ref)
            self.call_count += 1
            "#{ref}-#{call_count}"
          end
          cache_method :resolve, skip_cache: ->(ref) { ref != 'stable-id' }
        end
      end)
      SkipCacheFixture.call_count = 0
    end

    it 'never caches an argument for which skip_cache returns true' do
      first = SkipCacheFixture.resolve('HEAD')
      second = SkipCacheFixture.resolve('HEAD')

      expect(second).not_to eq(first)
      expect(SkipCacheFixture.call_count).to eq(2)
    end

    it 'still caches an argument for which skip_cache returns false' do
      first = SkipCacheFixture.resolve('stable-id')
      second = SkipCacheFixture.resolve('stable-id')

      expect(second).to eq(first)
      expect(SkipCacheFixture.call_count).to eq(1)
    end
  end
end
