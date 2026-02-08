# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe AsyncHttpPool::PayloadStore::FileStore do
  let(:temp_dir) { Dir.mktmpdir("payload_store_test") }
  let(:store) { described_class.new(directory: temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".register" do
    it "is registered as :file adapter" do
      expect(AsyncHttpPool::PayloadStore::Base.lookup(:file)).to eq(described_class)
    end
  end

  describe "#initialize" do
    it "creates directory if it doesn't exist" do
      new_dir = File.join(temp_dir, "nested", "dir")
      expect(File.exist?(new_dir)).to be false

      described_class.new(directory: new_dir)
      expect(File.exist?(new_dir)).to be true
    end

    it "defaults to system temp directory" do
      store = described_class.new
      expect(store.directory).to eq(Dir.tmpdir)
    end
  end

  describe "#store" do
    it "stores data as JSON file" do
      data = {"status" => 200, "body" => "test"}
      key = store.store("test-key", data)

      expect(key).to eq("test-key")
      expect(File.exist?(File.join(temp_dir, "test-key.json"))).to be true
    end

    it "overwrites existing data" do
      store.store("test-key", {"version" => 1})
      store.store("test-key", {"version" => 2})

      fetched = store.fetch("test-key")
      expect(fetched["version"]).to eq(2)
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
