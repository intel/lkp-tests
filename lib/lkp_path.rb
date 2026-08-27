#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

module LKP
  module Path
    class << self
      def src(*strs)
        File.join([LKP_SRC] + strs)
      end

      def etc(*strs)
        src('etc', *strs)
      end
    end
  end
end
