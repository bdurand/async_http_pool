# frozen_string_literal: true

require "spec_helper"

RSpec.describe "AsyncHttpPool::PayloadStore::S3Store", :s3 do
  before(:all) do
    skip "S3/Minio not available for testing" unless S3Helper.available?
  end

  let(:described_class) { AsyncHttpPool::PayloadStore::S3Store }

  let(:bucket) { S3Helper.test_bucket }
  let(:store) { described_class.new(bucket: bucket) }

  describe ".register" do
    it "is registered as :s3 adapter" do
      described_class
      expect(AsyncHttpPool::PayloadStore::Base.lookup(:s3)).to eq(described_class)
    end
  end

  describe "#initialize" do
    it "raises ArgumentError when bucket not provided" do
      expect { described_class.new(bucket: nil) }.to raise_error(ArgumentError, "S3 bucket is required")
    end

    it "accepts S3 bucket" do
      store = described_class.new(bucket: bucket)
      expect(store).to be_a(described_class)
    end

    it "accepts custom key_prefix" do
      store = described_class.new(bucket: bucket, key_prefix: "custom/prefix/")
      expect(store.key_prefix).to eq("custom/prefix/")
    end

    it "defaults key_prefix to async_http_pool/payloads/" do
      store = described_class.new(bucket: bucket)
      expect(store.key_prefix).to eq("async_http_pool/payloads/")
    end
  end

  describe "#store" do
    it "stores data as JSON in S3" do
      data = {"status" => 200, "body" => "test"}
      key = store.store("test-key", data)

      expect(key).to eq("test-key")

      object = bucket.object("async_http_pool/payloads/test-key")
      expect(object.exists?).to be true
      expect(JSON.parse(object.get.body.read)).to eq(data)
    end

    it "uses custom key_prefix" do
      store = described_class.new(bucket: bucket, key_prefix: "test/payloads/")
      data = {"status" => 200}
      store.store("test-key", data)

      object = bucket.object("test/payloads/test-key")
      expect(object.exists?).to be true
    end

    it "overwrites existing data" do
      store.store("test-key", {"version" => 1})
      store.store("test-key", {"version" => 2})

      fetched = store.fetch("test-key")
      expect(fetched["version"]).to eq(2)
    end

    it "sets content-type to application/json" do
      store.store("test-key", {"data" => "value"})

      object = bucket.object("async_http_pool/payloads/test-key")
      expect(object.content_type).to eq("application/json")
    end
  end

  describe "#fetch" do
    it "retrieves stored data" do
      data = {"status" => 200, "headers" => {"content-type" => "application/json"}}
      store.store("test-key", data)

      fetched = store.fetch("test-key")
      expect(fetched).to eq(data)
    end

    it "returns nil for non-existent keys" do
      expect(store.fetch("nonexistent")).to be_nil
    end
  end

  describe "#delete" do
    it "removes stored data" do
      store.store("test-key", {"data" => "value"})
      expect(store.fetch("test-key")).not_to be_nil

      result = store.delete("test-key")
      expect(result).to be true
      expect(store.fetch("test-key")).to be_nil
    end

    it "is idempotent for non-existent keys" do
      expect(store.delete("nonexistent")).to be true
      expect(store.delete("nonexistent")).to be true
    end
  end

  describe "#exists?" do
    it "returns true for existing keys" do
      store.store("test-key", {"data" => "value"})
      expect(store.exists?("test-key")).to be true
    end

    it "returns false for non-existent keys" do
      expect(store.exists?("nonexistent")).to be false
    end
  end

  describe "thread safety" do
    it "handles concurrent access safely" do
      threads = 10.times.map do |i|
        Thread.new do
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
end
