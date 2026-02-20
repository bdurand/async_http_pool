# frozen_string_literal: true

require "spec_helper"

RSpec.describe PatientHttp::RequestHelper do
  after do
    described_class.unregister_handler
  end

  describe ".register_handler" do
    it "raises when neither a callable nor a block is provided" do
      expect {
        described_class.register_handler
      }.to raise_error(ArgumentError, "Must provide a callable object or a block")
    end

    it "raises when both callable and block are provided" do
      callable = proc { |request:, callback:, callback_args: nil, raise_error_responses: nil| }

      expect {
        described_class.register_handler(callable) { |request:, callback:, callback_args: nil, raise_error_responses: nil| nil }
      }.to raise_error(ArgumentError, "Cannot provide both a callable object and a block")
    end

    it "raises when callable does not respond to call" do
      expect {
        described_class.register_handler(Object.new)
      }.to raise_error(ArgumentError, "Handler must be a callable object or a block")
    end

    it "raises when handler does not accept required keyword arguments" do
      handler = proc { |other_param: nil| }

      expect {
        described_class.register_handler(handler)
      }.to raise_error(ArgumentError, /Handler must accept keyword arguments: request, callback, callback_args, raise_error_responses/)
    end

    it "raises when handler is missing some required keyword arguments" do
      handler = proc { |request:, callback:| }

      expect {
        described_class.register_handler(handler)
      }.to raise_error(ArgumentError, /Missing: callback_args, raise_error_responses/)
    end

    it "accepts handlers with keyword rest parameter" do
      handler = proc { |**kwargs| }

      expect {
        described_class.register_handler(handler)
      }.not_to raise_error
    end

    it "accepts handlers with all required keyword arguments" do
      handler = proc { |request:, callback:, callback_args:, raise_error_responses:| }

      expect {
        described_class.register_handler(handler)
      }.not_to raise_error
    end

    it "accepts handlers with all required keyword arguments with defaults" do
      handler = proc { |request:, callback:, callback_args: nil, raise_error_responses: nil| }

      expect {
        described_class.register_handler(handler)
      }.not_to raise_error
    end

    it "raises when handler accepts positional parameters" do
      handler = proc { |context, request:, callback:, callback_args: nil, raise_error_responses: nil| }

      expect {
        described_class.register_handler(handler)
      }.to raise_error(ArgumentError, /Handler must not accept positional parameters/)
    end

    it "raises when handler has extra required keyword parameters" do
      handler = proc { |request:, callback:, callback_args:, raise_error_responses:, extra_param:| }

      expect {
        described_class.register_handler(handler)
      }.to raise_error(ArgumentError, /Handler must not have extra required keyword parameters.*Found: extra_param/)
    end

    it "accepts handlers with optional keyword parameters beyond the required ones" do
      handler = proc { |request:, callback:, callback_args: nil, raise_error_responses: nil, extra_param: nil| }

      expect {
        described_class.register_handler(handler)
      }.not_to raise_error
    end

    it "registers a callable object" do
      request = instance_double(PatientHttp::Request)
      callback = "TestCallback"
      callable = proc { |request:, callback:, callback_args: nil, raise_error_responses: nil| }

      described_class.register_handler(callable)
      described_class.execute(request: request, callback: callback)
    end

    it "registers a block" do
      request = instance_double(PatientHttp::Request)
      callback = "TestCallback"
      captured_request = nil
      captured_callback = nil

      described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
        captured_request = request
        captured_callback = callback
      end

      described_class.execute(request: request, callback: callback)

      expect(captured_request).to be(request)
      expect(captured_callback).to eq(callback)
    end
  end

  describe ".execute" do
    it "raises when no handler is registered" do
      expect {
        described_class.execute(request: instance_double(PatientHttp::Request), callback: "TestCallback")
      }.to raise_error(
        RuntimeError,
        "No request handler registered; you must register a PatientHttp::RequestHelper handler before executing requests"
      )
    end

    it "calls the registered handler with keyword arguments" do
      request = instance_double(PatientHttp::Request)
      callback = "TestCallback"
      captured_request = nil
      captured_callback = nil
      handler = lambda { |request:, callback:, callback_args: nil, raise_error_responses: nil|
        captured_request = request
        captured_callback = callback
      }

      described_class.register_handler(handler)

      described_class.execute(request: request, callback: callback)
      expect(captured_request).to be(request)
      expect(captured_callback).to eq(callback)
    end
  end

  describe "class-level request helpers" do
    it "builds a request from the class template and executes the registered handler" do
      captured_request = nil
      captured_callback = nil
      captured_callback_args = nil
      captured_raise_error_responses = nil

      described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
        captured_request = request
        captured_callback = callback
        captured_callback_args = callback_args
        captured_raise_error_responses = raise_error_responses
        "request-id-123"
      end

      result = TestService.async_get(
        "/users/42",
        callback: TestCallback,
        callback_args: {"user_id" => 42},
        params: {"expand" => "posts"},
        raise_error_responses: true
      )

      expect(result).to eq("request-id-123")
      expect(captured_callback).to eq(TestCallback)
      expect(captured_callback_args).to eq({"user_id" => 42})
      expect(captured_raise_error_responses).to eq(true)

      expect(captured_request).to be_a(PatientHttp::Request)
      expect(captured_request.http_method).to eq(:get)
      expect(captured_request.url).to eq("https://api.example.com/users/42?expand=posts")
      expect(captured_request.headers.to_h).to include("authorization" => "Bearer token")
      expect(captured_request.timeout).to eq(30)
    end

    it "merges template headers with per-request headers" do
      captured_request = nil

      described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
        captured_request = request
      end

      TestService.async_post(
        "/events",
        callback: "TestCallback",
        json: {"kind" => "created"},
        headers: {"X-Request-Id" => "abc123"}
      )

      request_headers = captured_request.headers.to_h
      expect(request_headers).to include("authorization" => "Bearer token")
      expect(request_headers).to include("x-request-id" => "abc123")
      expect(request_headers).to include("content-type" => "application/json; encoding=utf-8")
    end

    describe "HTTP method helpers" do
      let(:captured_request) { nil }

      before do
        @captured_request = nil
        described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
          @captured_request = request
        end
      end

      it "async_get sends GET requests" do
        TestService.async_get("/path", callback: TestCallback)
        expect(@captured_request.http_method).to eq(:get)
        expect(@captured_request.url).to eq("https://api.example.com/path")
      end

      it "async_post sends POST requests" do
        TestService.async_post("/path", callback: TestCallback, json: {"data" => "value"})
        expect(@captured_request.http_method).to eq(:post)
        expect(@captured_request.url).to eq("https://api.example.com/path")
      end

      it "async_put sends PUT requests" do
        TestService.async_put("/path", callback: TestCallback, body: "content")
        expect(@captured_request.http_method).to eq(:put)
        expect(@captured_request.url).to eq("https://api.example.com/path")
      end

      it "async_patch sends PATCH requests" do
        TestService.async_patch("/path", callback: TestCallback, json: {"field" => "updated"})
        expect(@captured_request.http_method).to eq(:patch)
        expect(@captured_request.url).to eq("https://api.example.com/path")
      end

      it "async_delete sends DELETE requests" do
        TestService.async_delete("/path", callback: TestCallback)
        expect(@captured_request.http_method).to eq(:delete)
        expect(@captured_request.url).to eq("https://api.example.com/path")
      end
    end
  end

  describe "instance-level request helpers" do
    it "delegates async_request through the including class" do
      captured_request = nil
      captured_callback = nil

      described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
        captured_request = request
        captured_callback = callback
      end

      service = TestService.new
      service.async_delete("/users/99", callback: TestCallback)

      expect(captured_request.http_method).to eq(:delete)
      expect(captured_request.url).to eq("https://api.example.com/users/99")
      expect(captured_callback).to eq(TestCallback)
    end

    it "accepts callback as a class name string" do
      captured_callback = nil

      described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
        captured_callback = callback
      end

      service = TestService.new
      service.async_put("/users/99", callback: "TestCallback")

      expect(captured_callback).to eq("TestCallback")
    end

    describe "HTTP method helpers" do
      before do
        @captured_request = nil
        described_class.register_handler do |request:, callback:, callback_args: nil, raise_error_responses: nil|
          @captured_request = request
        end
        @service = TestService.new
      end

      it "async_get sends GET requests" do
        @service.async_get("/resource", callback: TestCallback)
        expect(@captured_request.http_method).to eq(:get)
      end

      it "async_post sends POST requests" do
        @service.async_post("/resource", callback: TestCallback, json: {"key" => "value"})
        expect(@captured_request.http_method).to eq(:post)
      end

      it "async_put sends PUT requests" do
        @service.async_put("/resource", callback: TestCallback, body: "data")
        expect(@captured_request.http_method).to eq(:put)
      end

      it "async_patch sends PATCH requests" do
        @service.async_patch("/resource", callback: TestCallback, json: {"update" => "field"})
        expect(@captured_request.http_method).to eq(:patch)
      end

      it "async_delete sends DELETE requests" do
        @service.async_delete("/resource", callback: TestCallback)
        expect(@captured_request.http_method).to eq(:delete)
      end
    end
  end
end
