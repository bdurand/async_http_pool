# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Streaming Response Integration", :integration do
  let(:config) do
    AsyncHttpPool::Configuration.new(
      max_connections: 3,
      request_timeout: 10
    )
  end

  let(:processor) { AsyncHttpPool::Processor.new(config) }

  around do |example|
    # Disable WebMock for integration tests
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!

    test_web_server.start.ready?

    processor.run do
      example.run
    end
  ensure
    # Re-enable WebMock
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  it "handles multiple concurrent requests with delayed responses without blocking" do
    # Create 3 concurrent requests that each take 500ms
    # If they run concurrently (non-blocking), total time should be ~500ms
    # If they block each other (sequential), total time would be ~1500ms
    template = AsyncHttpPool::RequestTemplate.new(base_url: test_web_server.base_url)
    task_handlers = []

    start_time = Time.now

    3.times do |i|
      request = template.get("/delay/500")

      handler = TestTaskHandler.new({
        "class" => "Worker",
        "jid" => "jid-#{i}",
        "args" => [i]
      })
      task_handlers << handler
      task = AsyncHttpPool::RequestTask.new(
        request: request,
        task_handler: handler,
        callback: TestCallback
      )

      processor.enqueue(task)
    end

    # Wait for all requests to complete
    processor.wait_for_idle(timeout: 5)

    total_duration = Time.now - start_time

    # Verify all 3 requests completed
    all_completions = task_handlers.flat_map(&:completions)
    expect(all_completions.size).to eq(3)

    # Verify all completed successfully
    all_completions.each do |completion|
      response = completion[:response]
      expect(response.status).to eq(200)
      expect(response.duration).to be >= 0.5 # Each takes at least 500ms
    end

    # Key assertion: Total time should be ~500ms (concurrent execution)
    # NOT ~1500ms (sequential/blocking execution)
    # Allow some overhead for queueing and processing
    expect(total_duration).to be < 1.0
  end
end
