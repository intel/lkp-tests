#!/usr/bin/env ruby

LKP_SRC ||= ENV['LKP_SRC'] || File.dirname(__dir__)

require "#{LKP_SRC}/lib/git"

module LKP
  module Taggable
    def tagged_path
      return @tagged_path if @tagged_path

      git = Git.open

      commit = self['commit']
      tag = git.gcommit(commit).tag || commit

      @tagged_path = path.sub(commit, tag)
    end
  end
end
