# frozen_string_literal: true

# Test callback service that records all calls
class TestCallback
  @completion_calls = []
  @error_calls = []
  @mutex = Mutex.new

  class << self
    attr_reader :completion_calls, :error_calls

    def reset_calls!
      @mutex.synchronize do
        @completion_calls = []
        @error_calls = []
      end
    end

    def record_completion(response)
      @mutex.synchronize { @completion_calls << response }
    end

    def record_error(error)
      @mutex.synchronize { @error_calls << error }
    end
  end

  def on_complete(response)
    self.class.record_completion(response)
  end

  def on_error(error)
    self.class.record_error(error)
  end
end
