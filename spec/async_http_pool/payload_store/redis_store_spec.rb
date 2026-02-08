# frozen_string_literal: true

require "spec_helper"

RSpec.describe AsyncHttpPool::PayloadStore::RedisStore do
  before(:all) do
    skip "Redis not available for testing" unless RedisHelper.available?
  end

  let(:redis) { RedisHelper.redis }

  describe ".register" do
    it "is registered as :redis adapter" do
      described_class
      expect(AsyncHttpPool::PayloadStore::Base.lookup(:redis)).to eq(described_class)
    end
  end

  describe "#initialize" do
    it "raises ArgumentError when redis client not provided" do
      expect { described_class.new(redis: nil) }.to raise_error(ArgumentError, "redis client is required")
    end

    it "accepts redis client" do
      store = described_class.new(redis: redis)
      expect(store).to be_a(described_class)
    end

    it "accepts custom TTL" do
      store = described_class.new(redis: redis, ttl: 3600)
      expect(store.ttl).to eq(3600)
    end

    it "defaults TTL to nil" do
      store = described_class.new(redis: redis)
      expect(store.ttl).to be_nil
    end

    it "accepts custom key_prefix" do
      store = described_class.new(redis: redis, key_prefix: "custom:")
      expect(store.key_prefix).to eq("custom:")
    end

    it "defaults key_prefix to async_http_pool:payloads:" do
      store = described_class.new(redis: redis)
      expect(store.key_prefix).to eq("async_http_pool:payloads:")
    end
  end

  describe "#store" do
    it "stores data as JSON in Redis" do
      store = described_class.new(redis: redis)
      data = {"status" => 200, "body" => "test"}
      key = store.store("test-key", data)

      expect(key).to eq("test-key")
      stored = redis.get("async_http_pool:payloads:test-key")
      expect(stored).to eq(JSON.generate(data))
    end

    it "uses custom key_prefix" do
      store = described_class.new(redis: redis, key_prefix: "test:payloads:")
      data = {"status" => 200}
      store.store("test-key", data)

      expect(redis.get("test:payloads:test-key")).to eq(JSON.generate(data))
    end

    it "overwrites existing data" do
      store = described_class.new(redis: redis)
      store.store("test-key", {"version" => 1})
      store.store("test-key", {"version" => 2})

      fetched = store.fetch("test-key")
      expect(fetched["version"]).to eq(2)
    end

    it "sets TTL when configured" do
      store = described_class.new(redis: redis, ttl: 60)
      store.store("test-key", {"data" => "value"})

      ttl = redis.ttl("async_http_pool:payloads:test-key")
      expect(ttl).to be > 0
      expect(ttl).to be <= 60
    end

    it "does not set TTL when not configured" do
      store = described_class.new(redis: redis)
      store.store("test-key", {"data" => "value"})

      ttl = redis.ttl("async_http_pool:payloads:test-key")
      expect(ttl).to eq(-1)
    end
  end

  describe "#fetch" do
    it "retrieves stored data" do
      store = described_class.new(redis: redis)
      data = {"status" => 200, "headers" => {"content-type" => "application/json"}}
      store.store("test-key", data)

      fetched = store.fetch("test-key")
      expect(fetched).to eq(data)
    end

    it "returns nil for non-existent keys" do
      store = described_class.new(redis: redis)
      expect(store.fetch("nonexistent")).to be_nil
    end
  end

  describe "#delete" do
    it "removes stored data" do
      store = described_class.new(redis: redis)
      store.store("test-key", {"data" => "value"})
      expect(store.fetch("test-key")).not_to be_nil

      result = store.delete("test-key")
      expect(result).to be true
      expect(store.fetch("test-key")).to be_nil
    end

    it "is idempotent for non-existent keys" do
      store = described_class.new(redis: redis)
      expect(store.delete("nonexistent")).to be true
      expect(store.delete("nonexistent")).to be true
    end
  end

  describe "#exists?" do
    it "returns true for existing keys" do
      store = described_class.new(redis: redis)
      store.store("test-key", {"data" => "value"})
      expect(store.exists?("test-key")).to be true
    end

    it "returns false for non-existent keys" do
      store = described_class.new(redis: redis)
      expect(store.exists?("nonexistent")).to be false
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = 10.times.map do |i|
        Thread.new do
          store = described_class.new(redis: redis)
          key = "thread-#{i}"
          data = {"thread" => i, "data" => "x" * 1000}

          store.store(key, data)
          fetched = store.fetch(key)
          expect(fetched["thread"]).to eq(i)
          store.delete(key)
        end
      end

      threads.each(&:join)
    end
  end

  describe "round trip" do
    it "stores and retrieves complex data" do
      store = described_class.new(redis: redis)
      data = {
        "status" => 200,
        "headers" => {"content-type" => "application/json", "x-custom" => "value"},
        "body" => {"encoding" => "text", "value" => "large body " * 1000},
        "duration" => 0.5,
        "redirects" => ["http://old.url", "http://new.url"]
      }

      key = store.generate_key
      store.store(key, data)
      fetched = store.fetch(key)

      expect(fetched).to eq(data)
    end
  end

  describe "TTL expiration" do
    it "keys expire after TTL" do
      store = described_class.new(redis: redis, ttl: 0.1)
      store.store("expiring-key", {"data" => "value"})

      expect(store.exists?("expiring-key")).to be true

      sleep(0.11)

      expect(store.exists?("expiring-key")).to be false
      expect(store.fetch("expiring-key")).to be_nil
    end
  end
end
