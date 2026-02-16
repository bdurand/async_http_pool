# frozen_string_literal: true

module AsyncHttpPool
  # Data object representing the context of a request being processed.
  class RequestContext
    attr_reader :request, :callback, :callback_args, :raise_error_responses

    def initialize(request:, callback:, callback_args: nil, raise_error_responses: nil)
      @request = request
      @callback = callback
      @callback_args = callback_args
      @raise_error_responses = raise_error_responses
    end
  end
end
