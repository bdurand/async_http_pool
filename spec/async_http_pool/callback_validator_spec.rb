# frozen_string_literal: true

require "spec_helper"

RSpec.describe AsyncHttpPool::CallbackValidator do
  it "does not raise for valid callback class" do
    expect { described_class.validate!(TestCallback) }.not_to raise_error
  end

  it "does not raise for valid callback class name" do
    expect { described_class.validate!("TestCallback") }.not_to raise_error
  end

  it "raises if callback class is missing on_complete" do
    expect { described_class.validate!(Object) }.to raise_error(ArgumentError, /must define #on_complete/)
  end

  it "raises if callback class name does not exist" do
    expect { described_class.validate!("NonExistentCallback") }.to raise_error(NameError)
  end
end
