# frozen_string_literal: true

require "spec_helper"

RSpec.describe AsyncHttpPool::ClassHelper do
  describe ".resolve_class_name" do
    it "returns the class constant" do
      klass = described_class.resolve_class_name("AsyncHttpPool::ClassHelper")
      expect(klass).to eq(AsyncHttpPool::ClassHelper)
    end

    it "handles absolute class names" do
      klass = described_class.resolve_class_name("::AsyncHttpPool::ClassHelper")
      expect(klass).to eq(AsyncHttpPool::ClassHelper)
    end

    it "raises NameError for unknown class" do
      expect {
        described_class.resolve_class_name("NonExistent::ClassName")
      }.to raise_error(NameError)
    end

    it "returns nil for nil or empty string" do
      expect(described_class.resolve_class_name(nil)).to be_nil
      expect(described_class.resolve_class_name("")).to be_nil
    end
  end
end
