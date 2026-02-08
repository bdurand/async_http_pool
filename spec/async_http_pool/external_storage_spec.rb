# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe AsyncHttpPool::ExternalStorage do
  let(:temp_dir) { Dir.mktmpdir("external_storage_test") }
  let(:config) do
    c = AsyncHttpPool::Configuration.new
    c.register_payload_store(:test, adapter: :file, directory: temp_dir)
    c
  end
  let(:external_storage) { described_class.new(config) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#enabled?" do
    it "returns true when payload store is configured" do
      expect(external_storage.enabled?).to be true
    end

    it "returns false when no payload store is configured" do
      empty_config = AsyncHttpPool::Configuration.new
      empty_storage = described_class.new(empty_config)
      expect(empty_storage.enabled?).to be false
    end
  end

  describe "#store" do
    it "stores data in payload store and returns reference when max size not specified" do
      data = {"body" => "x"}
      result = external_storage.store(data)

      expect(result).to have_key("$ref")
      expect(result["$ref"]["store"]).to eq("test")
      expect(result["$ref"]["key"]).to match(/^[0-9a-f-]{36}$/)
    end

    it "returns original hash when below threshold" do
      small_data = {"status" => 200}
      result = external_storage.store(small_data, max_size: 100)
      expect(result).to eq(small_data)
    end

    it "stores externally and returns reference when above threshold" do
      large_data = {"body" => "x" * 200}
      result = external_storage.store(large_data, max_size: 100)

      expect(result).not_to eq(large_data)
      expect(result).to have_key("$ref")
      expect(result["$ref"]["store"]).to eq("test")
      expect(result["$ref"]["key"]).to match(/^[0-9a-f-]{36}$/)
    end

    it "raises PayloadStoreNotFoundError when no payload store is configured" do
      empty_config = AsyncHttpPool::Configuration.new
      empty_storage = described_class.new(empty_config)
      large_data = {"body" => "x" * 200}
      expect { empty_storage.store(large_data) }.to raise_error(AsyncHttpPool::ExternalStorage::PayloadStoreNotFoundError)
    end
  end

  describe ".storage_ref?" do
    it "returns true for storage references" do
      ref_data = {"$ref" => {"store" => "test", "key" => "abc123"}}
      expect(described_class.storage_ref?(ref_data)).to be true
    end

    it "returns false for regular hashes" do
      regular_data = {"status" => 200}
      expect(described_class.storage_ref?(regular_data)).to be false
    end

    it "returns false for non-hashes" do
      expect(described_class.storage_ref?(nil)).to be false
      expect(described_class.storage_ref?(123)).to be false
      expect(described_class.storage_ref?("string")).to be false
    end
  end

  describe "#fetch" do
    it "fetches stored data" do
      large_data = {"body" => "x" * 200}
      ref_data = external_storage.store(large_data)

      result = external_storage.fetch(ref_data)
      expect(result).to eq(large_data)
    end

    it "raises error if not a reference" do
      regular_data = {"status" => 200}
      expect { external_storage.fetch(regular_data) }.to raise_error(ArgumentError, /Not a storage reference/)
    end

    it "raises error when store is not registered" do
      ref_data = {"$ref" => {"store" => "nonexistent", "key" => "abc123"}}

      expect { external_storage.fetch(ref_data) }.to raise_error(
        AsyncHttpPool::ExternalStorage::PayloadStoreNotFoundError,
        /Payload store 'nonexistent' not registered/
      )
    end

    it "raises error when payload is not found" do
      ref_data = {"$ref" => {"store" => "test", "key" => "nonexistent-key"}}

      expect { external_storage.fetch(ref_data) }.to raise_error(
        AsyncHttpPool::ExternalStorage::PayloadNotFoundError,
        /Stored payload not found/
      )
    end
  end

  describe "#delete" do
    it "deletes stored payload" do
      large_data = {"body" => "x" * 200}
      ref_data = external_storage.store(large_data)

      key = ref_data["$ref"]["key"]
      store = config.payload_store

      expect(store.exists?(key)).to be true

      external_storage.delete(ref_data)
      expect(store.exists?(key)).to be false
    end

    it "is idempotent" do
      large_data = {"body" => "x" * 200}
      ref_data = external_storage.store(large_data)

      external_storage.delete(ref_data)
      expect { external_storage.delete(ref_data) }.not_to raise_error
    end

    it "does nothing for non-reference hashes" do
      regular_data = {"status" => 200}
      expect { external_storage.delete(regular_data) }.not_to raise_error
    end

    it "handles nil gracefully" do
      expect { external_storage.delete(nil) }.not_to raise_error
    end
  end

  describe "round trip" do
    it "stores and fetches Response data" do
      response = AsyncHttpPool::Response.new(
        status: 200,
        headers: {"content-type" => "application/json"},
        body: "x" * 200,
        duration: 0.1,
        request_id: "test-id",
        url: "http://example.com",
        http_method: :get
      )

      original_data = response.as_json
      ref_data = external_storage.store(original_data)

      expect(described_class.storage_ref?(ref_data)).to be true

      fetched_data = external_storage.fetch(ref_data)
      loaded = AsyncHttpPool::Response.load(fetched_data)

      expect(loaded.status).to eq(200)
      expect(loaded.body).to eq("x" * 200)

      external_storage.delete(ref_data)
      expect { external_storage.fetch(ref_data) }.to raise_error(/Stored payload not found/)
    end

    it "stores and fetches Request data" do
      request = AsyncHttpPool::Request.new(
        :post,
        "http://example.com",
        body: "x" * 200,
        headers: {"content-type" => "application/json"}
      )

      original_data = request.as_json
      ref_data = external_storage.store(original_data)

      expect(described_class.storage_ref?(ref_data)).to be true

      fetched_data = external_storage.fetch(ref_data)
      loaded = AsyncHttpPool::Request.load(fetched_data)

      expect(loaded.http_method).to eq(:post)
      expect(loaded.body).to eq("x" * 200)
    end
  end

  describe "migration between stores" do
    let(:old_dir) { Dir.mktmpdir("old_store") }
    let(:new_dir) { Dir.mktmpdir("new_store") }

    after do
      FileUtils.rm_rf(old_dir)
      FileUtils.rm_rf(new_dir)
    end

    it "reads from old store while writing to new store" do
      # Setup old store config and create a stored payload
      old_config = AsyncHttpPool::Configuration.new
      old_config.register_payload_store(:old_store, adapter: :file, directory: old_dir)
      old_storage = described_class.new(old_config)

      large_data = {"body" => "x" * 200}
      old_ref_data = old_storage.store(large_data)
      expect(old_ref_data["$ref"]["store"]).to eq("old_store")

      # New config has both stores registered; new_store is the default (registered last)
      migration_config = AsyncHttpPool::Configuration.new
      migration_config.register_payload_store(:old_store, adapter: :file, directory: old_dir)
      migration_config.register_payload_store(:new_store, adapter: :file, directory: new_dir)
      migration_storage = described_class.new(migration_config)

      # New writes go to new store
      new_large_data = {"body" => "y" * 200}
      new_ref_data = migration_storage.store(new_large_data)
      expect(new_ref_data["$ref"]["store"]).to eq("new_store")

      # Can still fetch from old store
      expect(migration_storage.fetch(old_ref_data)).to eq(large_data)

      # Can fetch from new store
      expect(migration_storage.fetch(new_ref_data)).to eq(new_large_data)
    end
  end
end
