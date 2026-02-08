# frozen_string_literal: true

class RedisHelper
  class << self
    def available?
      @available ||= begin
        require "redis"
        true
      rescue LoadError
        false
      end
    end

    def setup
      return unless available?

      @redis = Redis.new
    end

    attr_reader :redis

    def flushdb
      redis&.flushdb
    end
  end
end
