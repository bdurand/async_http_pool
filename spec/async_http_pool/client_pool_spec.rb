# frozen_string_literal: true

require "spec_helper"

RSpec.describe AsyncHttpPool::ClientPool do
  let(:pool) { described_class.new(max_size: 3, retries: 3) }

  after do
    pool.close
  end

  describe "#initialize" do
    it "sets max_size" do
      expect(pool.max_size).to eq(3)
    end

    it "sets retries" do
      expect(pool.retries).to eq(3)
    end

    it "sets connection_timeout when provided" do
      pool_with_timeout = described_class.new(max_size: 3, connection_timeout: 10)
      expect(pool_with_timeout.connection_timeout).to eq(10)
      pool_with_timeout.close
    end

    it "sets proxy_url when provided" do
      pool_with_proxy = described_class.new(max_size: 3, proxy_url: "http://proxy.example.com:8080")
      expect(pool_with_proxy.proxy_url).to eq("http://proxy.example.com:8080")
      pool_with_proxy.close
    end
  end

  describe "#size" do
    it "returns 0 for empty pool" do
      expect(pool.size).to eq(0)
    end
  end

  describe "#close" do
    it "handles multiple close calls gracefully" do
      pool.close
      expect { pool.close }.not_to raise_error
    end
  end
end
