# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Capacity Limit Integration", :integration do
  include Async::RSpec::Reactor

  let(:config) do
    AsyncHttpPool::Configuration.new(
      max_connections: 2, # Set low limit for testing
      request_timeout: 10
    )
  end

  let!(:processor) { AsyncHttpPool::Processor.new(config) }

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

  describe "enforcing max_connections limit" do
    it "raises error when attempting to exceed capacity and allows enqueue after request completes" do
      # Build client
      template = AsyncHttpPool::RequestTemplate.new(base_url: test_web_server.base_url)
      task_handlers = []

      # Enqueue first long-running request
      request1 = template.get("/delay/250")
      handler1 = TestTaskHandler.new({
        "class" => "Worker",
        "jid" => "jid-1",
        "args" => ["arg1"]
      })
      task_handlers << handler1
      request_task1 = AsyncHttpPool::RequestTask.new(
        request: request1,
        task_handler: handler1,
        callback: TestCallback
      )
      processor.enqueue(request_task1)

      # Enqueue second long-running request
      request2 = template.get("/delay/250")
      handler2 = TestTaskHandler.new({
        "class" => "Worker",
        "jid" => "jid-2",
        "args" => ["arg2"]
      })
      task_handlers << handler2
      request_task2 = AsyncHttpPool::RequestTask.new(
        request: request2,
        task_handler: handler2,
        callback: TestCallback
      )
      processor.enqueue(request_task2)

      # Wait for both requests to start processing
      processor.wait_for_processing

      # Attempt to enqueue third request - should raise error
      request3 = template.get("/delay/100")
      handler3 = TestTaskHandler.new({
        "class" => "Worker",
        "jid" => "jid-3",
        "args" => ["arg3"]
      })
      task_handlers << handler3
      request_task3 = AsyncHttpPool::RequestTask.new(
        request: request3,
        task_handler: handler3,
        callback: TestCallback
      )

      # Wait for requests to start processing
      processor.wait_for_processing

      # Should raise error due to capacity limit
      expect {
        processor.enqueue(request_task3)
      }.to raise_error(AsyncHttpPool::MaxCapacityError)

      processor.wait_for_idle

      # Now we should be able to enqueue the third request
      expect {
        processor.enqueue(request_task3)
      }.not_to raise_error

      # Wait for third request to complete
      processor.wait_for_idle

      # Verify all 3 requests completed successfully
      all_completions = task_handlers.flat_map(&:completions)
      all_errors = task_handlers.flat_map(&:errors)
      expect(all_completions.size).to eq(3)
      expect(all_errors.size).to eq(0)

      # Verify processor is still running
      expect(processor.running?).to be true
    end
  end
end
