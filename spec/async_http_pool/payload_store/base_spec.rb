# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
RSpec.describe AsyncHttpPool::PayloadStore::Base do
  describe ".register and .lookup" do
    let(:test_class) { Class.new(described_class) }

    after do
      # Clean up any test registrations by looking up and deleting if exists
      # Access via the class singleton to properly access instance variables
      registry = described_class.send(:registry)
      mutex = described_class.send(:registry_mutex)
      mutex.synchronize { registry.delete(:test_store) }
    end

    it "registers and looks up store adapters" do
      described_class.register(:test_store, test_class)
      expect(described_class.lookup(:test_store)).to eq(test_class)
    end

    it "accepts string names and converts to symbols" do
      described_class.register("test_store", test_class)
      expect(described_class.lookup("test_store")).to eq(test_class)
    end

    it "returns nil for unregistered adapters" do
      expect(described_class.lookup(:nonexistent)).to be_nil
    end
  end

  describe ".create" do
    it "creates a store instance from a registered adapter" do
      store = described_class.create(:file)
      expect(store).to be_a(AsyncHttpPool::PayloadStore::FileStore)
    end

    it "passes options to the adapter constructor" do
      dir = Dir.mktmpdir
      store = described_class.create(:file, directory: dir)
      expect(store.directory).to eq(dir)
    ensure
      FileUtils.rm_rf(dir)
    end

    it "raises ArgumentError for unknown adapters" do
      expect { described_class.create(:nonexistent) }.to raise_error(
        ArgumentError,
        /Unknown payload store adapter: :nonexistent/
      )
    end
  end

  describe ".registered_adapters" do
    it "lists all registered adapter names" do
      adapters = described_class.registered_adapters
      expect(adapters).to include(:file)
    end
  end

  describe "#generate_key" do
    let(:store) { AsyncHttpPool::PayloadStore::FileStore.new }

    it "generates unique UUID keys" do
      key1 = store.generate_key
      key2 = store.generate_key

      expect(key1).to match(/^[0-9a-f-]{36}$/)
      expect(key2).to match(/^[0-9a-f-]{36}$/)
      expect(key1).not_to eq(key2)
    end
  end

  describe "abstract methods" do
    let(:base_instance) { described_class.new }

    it "raises NotImplementedError for #store" do
      expect { base_instance.store("key", {}) }.to raise_error(
        NotImplementedError,
        /must implement #store/
      )
    end

    it "raises NotImplementedError for #fetch" do
      expect { base_instance.fetch("key") }.to raise_error(
        NotImplementedError,
        /must implement #fetch/
      )
    end

    it "raises NotImplementedError for #delete" do
      expect { base_instance.delete("key") }.to raise_error(
        NotImplementedError,
        /must implement #delete/
      )
    end
  end
end
