# frozen_string_literal: true

# Test implementation of AsyncHttpPool::TaskHandler that records all lifecycle
# calls without any Sidekiq dependency. Used in async_http_pool specs.
class TestTaskHandler < AsyncHttpPool::TaskHandler
  attr_reader :completions, :errors, :retries, :job_data

  def initialize(job_data = {})
    @job_data = job_data
    @completions = []
    @errors = []
    @retries = []
  end

  def on_complete(response, callback)
    @completions << {response: response, callback: callback}
  end

  def on_error(error, callback)
    @errors << {error: error, callback: callback}
  end

  def retry
    @retries << @job_data
    "retry-#{SecureRandom.uuid}"
  end
end
