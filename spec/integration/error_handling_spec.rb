# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Error Handling Integration", :integration do
  include Async::RSpec::Reactor

  let(:config) do
    AsyncHttpPool::Configuration.new(
      max_connections: 10,
      request_timeout: 5
    )
  end

  let(:processor) { AsyncHttpPool::Processor.new(config) }

  around do |example|
    # Disable WebMock completely for integration tests
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!

    processor.run do
      example.run
    end
  ensure
    # Re-enable WebMock
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  describe "timeout errors" do
    it "calls error handler with timeout error when request exceeds timeout" do
      # Make request with short timeout (use a longer delay to ensure timeout)
      template = AsyncHttpPool::RequestTemplate.new(base_url: test_web_server.base_url, timeout: 0.1)
      request = template.get("/delay/5000")

      handler = TestTaskHandler.new({"class" => "Worker", "jid" => "timeout-test", "args" => []})
      request_task = AsyncHttpPool::RequestTask.new(
        request: request,
        task_handler: handler,
        callback: TestCallback,
        callback_args: {"arg" => "timeout_arg"}
      )

      processor.enqueue(request_task)
      processor.wait_for_idle

      # Verify on_error was called
      expect(handler.errors.size).to eq(1)
      expect(handler.completions.size).to eq(0)

      error = handler.errors.first[:error]
      expect(error).to be_a(AsyncHttpPool::Error)
      expect(error.error_type).to eq(:timeout)
      expect(error.error_class.name).to match(/Timeout/)
      expect(error.callback_args.as_json).to eq({"arg" => "timeout_arg"})
    end
  end

  describe "connection errors" do
    it "calls error handler with connection error when server is not listening" do
      # Make request to a port that's not listening
      template = AsyncHttpPool::RequestTemplate.new(base_url: "http://127.0.0.1:1")
      request = template.get("/nowhere")

      handler = TestTaskHandler.new({"class" => "Worker", "jid" => "conn-test", "args" => []})
      request_task = AsyncHttpPool::RequestTask.new(
        request: request,
        task_handler: handler,
        callback: TestCallback,
        callback_args: {"arg" => "connection_arg"}
      )

      processor.enqueue(request_task)
      processor.wait_for_idle

      # Verify on_error was called
      expect(handler.errors.size).to eq(1)
      expect(handler.completions.size).to eq(0)

      error = handler.errors.first[:error]
      expect(error).to be_a(AsyncHttpPool::Error)
      expect(error.error_type).to eq(:connection)
      expect(error.error_class.name).to match(/Errno::E/)
      expect(error.message).to match(/refused|reset|connection/i)
      expect(error.callback_args.as_json).to eq({"arg" => "connection_arg"})
    end
  end

  describe "HTTP error responses" do
    it "calls completion handler for 4xx responses (they are valid HTTP responses)" do
      template = AsyncHttpPool::RequestTemplate.new(base_url: test_web_server.base_url)
      request = template.get("/test/404")

      handler = TestTaskHandler.new({"class" => "Worker", "jid" => "404-test", "args" => []})
      request_task = AsyncHttpPool::RequestTask.new(
        request: request,
        task_handler: handler,
        callback: TestCallback,
        callback_args: {"status" => "missing"}
      )

      processor.enqueue(request_task)
      processor.wait_for_idle

      # 404 is a valid HTTP response, so on_complete is called
      expect(handler.completions.size).to eq(1)
      expect(handler.errors.size).to eq(0)

      response = handler.completions.first[:response]
      expect(response.status).to eq(404)
      expect(response.client_error?).to be true
      expect(response.callback_args.as_json).to eq({"status" => "missing"})
    end

    it "calls completion handler for 5xx responses (they are valid HTTP responses)" do
      template = AsyncHttpPool::RequestTemplate.new(base_url: test_web_server.base_url)
      request = template.get("/test/503")

      handler = TestTaskHandler.new({"class" => "Worker", "jid" => "503-test", "args" => []})
      request_task = AsyncHttpPool::RequestTask.new(
        request: request,
        task_handler: handler,
        callback: TestCallback,
        callback_args: {"status" => "unavailable"}
      )

      processor.enqueue(request_task)
      processor.wait_for_idle

      # 503 is a valid HTTP response, so on_complete is called
      expect(handler.completions.size).to eq(1)
      expect(handler.errors.size).to eq(0)

      response = handler.completions.first[:response]
      expect(response.status).to eq(503)
      expect(response.server_error?).to be true
      expect(response.callback_args.as_json).to eq({"status" => "unavailable"})
    end

    it "calls error handler with HttpError when raise_error_responses is enabled" do
      template = AsyncHttpPool::RequestTemplate.new(base_url: test_web_server.base_url)
      request = template.get("/test/404")

      handler = TestTaskHandler.new({"class" => "Worker", "jid" => "404-error-test", "args" => []})
      request_task = AsyncHttpPool::RequestTask.new(
        request: request,
        task_handler: handler,
        callback: TestCallback,
        callback_args: {"status" => "missing"},
        raise_error_responses: true
      )

      processor.enqueue(request_task)
      processor.wait_for_idle

      # With raise_error_responses, 404 should call on_error with HttpError
      expect(handler.errors.size).to eq(1)
      expect(handler.completions.size).to eq(0)

      error = handler.errors.first[:error]
      expect(error).to be_a(AsyncHttpPool::HttpError)
      expect(error.status).to eq(404)
      expect(error.url).to include("/test/404")
      expect(error.http_method).to eq(:get)
      expect(error.response).to be_a(AsyncHttpPool::Response)
      expect(error.response.status).to eq(404)
      expect(error.response.client_error?).to be true
      expect(error.callback_args.as_json).to eq({"status" => "missing"})
    end
  end
end
