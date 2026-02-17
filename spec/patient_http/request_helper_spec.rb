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
      callable = proc { |_request_context| }

      expect {
        described_class.register_handler(callable) { |_request_context| nil }
      }.to raise_error(ArgumentError, "Cannot provide both a callable object and a block")
    end

    it "raises when callable does not respond to call" do
      expect {
        described_class.register_handler(Object.new)
      }.to raise_error(ArgumentError, "Handler must be a callable object or a block")
    end

    it "registers a callable object" do
      request_context = instance_double(PatientHttp::RequestContext)
      callable = instance_double(Proc)

      expect(callable).to receive(:call).with(request_context)

      described_class.register_handler(callable)
      described_class.execute(request_context)
    end

    it "registers a block" do
      request_context = instance_double(PatientHttp::RequestContext)
      captured_context = nil

      described_class.register_handler do |context|
        captured_context = context
      end

      described_class.execute(request_context)

      expect(captured_context).to be(request_context)
    end
  end

  describe ".execute" do
    it "raises when no handler is registered" do
      expect {
        described_class.execute(instance_double(PatientHttp::RequestContext))
      }.to raise_error(
        RuntimeError,
        "No request handler registered; you must register a handler before executing requests"
      )
    end

    it "calls the registered handler with the request context" do
      request_context = instance_double(PatientHttp::RequestContext)
      result_context = nil
      handler = lambda { |context| result_context = context }

      described_class.register_handler(handler)

      described_class.execute(request_context)
      expect(result_context).to be(request_context)
    end
  end

  describe "class-level request helpers" do
    it "builds a request from the class template and executes the registered handler" do
      captured_context = nil

      described_class.register_handler do |request_context|
        captured_context = request_context
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
      expect(captured_context).to be_a(PatientHttp::RequestContext)
      expect(captured_context.callback).to eq(TestCallback)
      expect(captured_context.callback_args).to eq({"user_id" => 42})
      expect(captured_context.raise_error_responses).to eq(true)

      request = captured_context.request
      expect(request).to be_a(PatientHttp::Request)
      expect(request.http_method).to eq(:get)
      expect(request.url).to eq("https://api.example.com/users/42?expand=posts")
      expect(request.headers.to_h).to include("authorization" => "Bearer token")
      expect(request.timeout).to eq(30)
    end

    it "merges template headers with per-request headers" do
      captured_context = nil

      described_class.register_handler do |request_context|
        captured_context = request_context
      end

      TestService.async_post(
        "/events",
        callback: "TestCallback",
        json: {"kind" => "created"},
        headers: {"X-Request-Id" => "abc123"}
      )

      request_headers = captured_context.request.headers.to_h
      expect(request_headers).to include("authorization" => "Bearer token")
      expect(request_headers).to include("x-request-id" => "abc123")
      expect(request_headers).to include("content-type" => "application/json; encoding=utf-8")
    end

    describe "HTTP method helpers" do
      let(:captured_context) { nil }

      before do
        @captured_context = nil
        described_class.register_handler do |request_context|
          @captured_context = request_context
        end
      end

      it "async_get sends GET requests" do
        TestService.async_get("/path", callback: TestCallback)
        expect(@captured_context.request.http_method).to eq(:get)
        expect(@captured_context.request.url).to eq("https://api.example.com/path")
      end

      it "async_post sends POST requests" do
        TestService.async_post("/path", callback: TestCallback, json: {"data" => "value"})
        expect(@captured_context.request.http_method).to eq(:post)
        expect(@captured_context.request.url).to eq("https://api.example.com/path")
      end

      it "async_put sends PUT requests" do
        TestService.async_put("/path", callback: TestCallback, body: "content")
        expect(@captured_context.request.http_method).to eq(:put)
        expect(@captured_context.request.url).to eq("https://api.example.com/path")
      end

      it "async_patch sends PATCH requests" do
        TestService.async_patch("/path", callback: TestCallback, json: {"field" => "updated"})
        expect(@captured_context.request.http_method).to eq(:patch)
        expect(@captured_context.request.url).to eq("https://api.example.com/path")
      end

      it "async_delete sends DELETE requests" do
        TestService.async_delete("/path", callback: TestCallback)
        expect(@captured_context.request.http_method).to eq(:delete)
        expect(@captured_context.request.url).to eq("https://api.example.com/path")
      end
    end
  end

  describe "instance-level request helpers" do
    it "delegates async_request through the including class" do
      captured_context = nil

      described_class.register_handler do |request_context|
        captured_context = request_context
      end

      service = TestService.new
      service.async_delete("/users/99", callback: TestCallback)

      expect(captured_context.request.http_method).to eq(:delete)
      expect(captured_context.request.url).to eq("https://api.example.com/users/99")
      expect(captured_context.callback).to eq(TestCallback)
    end

    it "accepts callback as a class name string" do
      captured_context = nil

      described_class.register_handler do |request_context|
        captured_context = request_context
      end

      service = TestService.new
      service.async_put("/users/99", callback: "TestCallback")

      expect(captured_context.callback).to eq("TestCallback")
    end

    describe "HTTP method helpers" do
      before do
        @captured_context = nil
        described_class.register_handler do |request_context|
          @captured_context = request_context
        end
        @service = TestService.new
      end

      it "async_get sends GET requests" do
        @service.async_get("/resource", callback: TestCallback)
        expect(@captured_context.request.http_method).to eq(:get)
      end

      it "async_post sends POST requests" do
        @service.async_post("/resource", callback: TestCallback, json: {"key" => "value"})
        expect(@captured_context.request.http_method).to eq(:post)
      end

      it "async_put sends PUT requests" do
        @service.async_put("/resource", callback: TestCallback, body: "data")
        expect(@captured_context.request.http_method).to eq(:put)
      end

      it "async_patch sends PATCH requests" do
        @service.async_patch("/resource", callback: TestCallback, json: {"update" => "field"})
        expect(@captured_context.request.http_method).to eq(:patch)
      end

      it "async_delete sends DELETE requests" do
        @service.async_delete("/resource", callback: TestCallback)
        expect(@captured_context.request.http_method).to eq(:delete)
      end
    end
  end
end
