# frozen_string_literal: true

module AsyncHttpPool
  # Mixin that provides a compact API for scheduling async HTTP requests.
  #
  # Include this module in your class to get instance-level and class-level helpers for building
  # requests and dispatching them through a registered handler.
  #
  # This module allows you to use the same interface for making HTTP requests while swapping out
  # the underlying queueing mechanism for handling responses asynchronously. By registering a
  # custom handler, you can integrate with any job queue system (Sidekiq, Solid Queue, etc.)
  # without changing your application code that makes HTTP requests. This decouples your request
  # interface from your async processing infrastructure.
  #
  # The common workflow is:
  # 1. Register a global request handler with {.register_handler}.
  # 2. Include this module in a class.
  # 3. Optionally configure defaults with {.request_template}.
  # 4. Call `async_get`, `async_post`, `async_put`, `async_patch`, `async_delete`, or
  #    `async_request`.
  #
  # @example Register a handler
  #   AsyncHttpPool::RequestHelper.register_handler do |request_context|
  #     # Convert request_context into your app-specific task/enqueue operation
  #     # and return the request id
  #   end
  #
  # @example Include in a class and enqueue requests
  #   class ApiClient
  #     include AsyncHttpPool::RequestHelper
  #
  #     request_template base_url: "https://api.example.com", headers: {"Authorization" => "Bearer token"}
  #
  #     def fetch_user(user_id)
  #       async_get("/users/#{user_id}", callback: UserCallback, callback_args: {"user_id" => user_id})
  #     end
  #   end
  module RequestHelper
    @handler = nil

    extend self

    class << self
      # Hooks helper behavior into the including class.
      #
      # Extends the class with {.ClassMethods} and initializes template storage.
      #
      # @param base [Class] class including this module
      # @return [void]
      def included(base)
        base.extend(ClassMethods)
        base.instance_variable_set(:@async_http_pool_request_template, nil)
      end

      # Registers a request handler that will be called to process each request.
      # The handler must be a callable object (responds to `call`) or a block.
      #
      # The handler will receive a RequestContext object with the request and callback information.
      # It should return the request id for the enqueued request.
      #
      # @param callable [#call, nil] A callable object that will handle requests
      # @yield [RequestContext] If a block is given, it will be used as the request handler
      # @raise [ArgumentError] if neither a callable nor a block is provided, or if both are provided
      # @raise [ArgumentError] if the provided callable does not respond to `call`
      # @return [void]
      def register_handler(callable = nil, &block)
        raise ArgumentError.new("Must provide a callable object or a block") unless callable || block_given?
        raise ArgumentError.new("Cannot provide both a callable object and a block") if callable && block_given?

        handler = callable || block
        unless handler.respond_to?(:call)
          raise ArgumentError.new("Handler must be a callable object or a block")
        end

        @handler = handler
      end

      # Unregisters the current request handler.
      #
      # @return [void]
      def unregister_handler
        @handler = nil
      end

      # Executes the registered request handler with the given request context.
      #
      # @param request_context [RequestContext] the context of the request to handle
      # @raise [RuntimeError] if no handler is registered
      # @return [Object] return value from the registered request handler
      def execute(request_context)
        raise "No request handler registered; you must register a handler before executing requests" unless @handler

        @handler.call(request_context)
      end
    end

    module HttpMethodHelpers
      # Enqueues an asynchronous HTTP GET request.
      #
      # @param uri [String] absolute URL or path (when using a request template)
      # @param callback [Class, String] callback class to handle the response
      # @param kwargs [Hash] forwarded to `async_request`
      # @return [Object] return value from the registered request handler
      def async_get(uri, callback:, **kwargs)
        async_request(:get, uri, callback: callback, **kwargs)
      end

      # Enqueues an asynchronous HTTP POST request.
      #
      # @param uri [String] absolute URL or path (when using a request template)
      # @param callback [Class, String] callback class to handle the response
      # @param kwargs [Hash] forwarded to `async_request`
      # @return [Object] return value from the registered request handler
      def async_post(uri, callback:, **kwargs)
        async_request(:post, uri, callback: callback, **kwargs)
      end

      # Enqueues an asynchronous HTTP PUT request.
      #
      # @param uri [String] absolute URL or path (when using a request template)
      # @param callback [Class, String] callback class to handle the response
      # @param kwargs [Hash] forwarded to `async_request`
      # @return [Object] return value from the registered request handler
      def async_put(uri, callback:, **kwargs)
        async_request(:put, uri, callback: callback, **kwargs)
      end

      # Enqueues an asynchronous HTTP PATCH request.
      #
      # @param uri [String] absolute URL or path (when using a request template)
      # @param callback [Class, String] callback class to handle the response
      # @param kwargs [Hash] forwarded to `async_request`
      # @return [Object] return value from the registered request handler
      def async_patch(uri, callback:, **kwargs)
        async_request(:patch, uri, callback: callback, **kwargs)
      end

      # Enqueues an asynchronous HTTP DELETE request.
      #
      # @param uri [String] absolute URL or path (when using a request template)
      # @param callback [Class, String] callback class to handle the response
      # @param kwargs [Hash] forwarded to `async_request`
      # @return [Object] return value from the registered request handler
      def async_delete(uri, callback:, **kwargs)
        async_request(:delete, uri, callback: callback, **kwargs)
      end
    end

    module ClassMethods
      include HttpMethodHelpers

      # Defines a default request template for this class.
      #
      # Requests created with the helper methods merge these defaults unless explicitly overridden.
      #
      # @param base_url [String, nil] optional base URL used to resolve relative request URLs
      # @param headers [Hash] default headers for requests
      # @param params [Hash, nil] default query parameters for requests
      # @param timeout [Float] default timeout in seconds
      # @return [void]
      def request_template(base_url: nil, headers: {}, params: nil, timeout: 30)
        @async_http_pool_request_template = RequestTemplate.new(
          base_url: base_url,
          headers: headers,
          params: params,
          timeout: timeout
        )
      end

      # Builds and dispatches an asynchronous HTTP request.
      #
      # When a request template is configured, the request is built from the template. Otherwise,
      # it is built directly from the provided arguments.
      #
      # @param method [Symbol] HTTP method (`:get`, `:post`, `:put`, `:patch`, `:delete`)
      # @param url [String] absolute URL or path (when using a request template)
      # @param callback [Class, String] callback class to handle the response
      # @param headers [Hash, nil] request headers
      # @param body [String, nil] raw request body
      # @param json [Hash, Array, nil] JSON payload encoded by the request layer
      # @param params [Hash, nil] query parameters
      # @param timeout [Numeric, nil] timeout in seconds for this request
      # @param raise_error_responses [Boolean, nil] when true, non-success responses are reported as errors
      # @param callback_args [Hash, nil] JSON-compatible callback arguments
      # @return [Object] return value from the registered request handler
      def async_request(
        method,
        url,
        callback:,
        headers: nil,
        body: nil,
        json: nil,
        params: nil,
        timeout: nil,
        raise_error_responses: nil,
        callback_args: nil
      )
        template = async_request_template
        kwargs = {body: body, json: json, headers: headers, params: params, timeout: timeout}
        request = if template
          template.request(method, url, **kwargs)
        else
          Request.new(method, url, **kwargs)
        end

        request_context = RequestContext.new(request: request, callback: callback, callback_args: callback_args, raise_error_responses: raise_error_responses)
        RequestHelper.execute(request_context)
      end

      # Returns the RequestTemplate defined for this class or its ancestors, or nil if none is defined.
      # This allows subclasses to inherit the request template from their parent class if they don't define their
      # own.
      #
      # @return [RequestTemplate, nil] the request template for this class or its ancestors
      # @api private
      def async_request_template
        return @async_http_pool_request_template if @async_http_pool_request_template
        return superclass.async_request_template if superclass.include?(AsyncHttpPool::RequestHelper)

        nil
      end
    end

    # Dispatches an asynchronous HTTP request from an instance context.
    #
    # This delegates to {.ClassMethods#async_request} on the including class.
    #
    # @param method [Symbol] HTTP method (`:get`, `:post`, `:put`, `:patch`, `:delete`)
    # @param url [String] absolute URL or path (when using a request template)
    # @param callback [Class, String] callback class to handle the response
    # @param headers [Hash, nil] request headers
    # @param body [String, nil] raw request body
    # @param json [Hash, Array, nil] JSON payload encoded by the request layer
    # @param params [Hash, nil] query parameters
    # @param timeout [Numeric, nil] timeout in seconds for this request
    # @param raise_error_responses [Boolean, nil] when true, non-success responses are reported as errors
    # @param callback_args [Hash, nil] JSON-compatible callback arguments
    # @return [Object] return value from the registered request handler
    def async_request(
      method,
      url,
      callback:,
      headers: nil,
      body: nil,
      json: nil,
      params: nil,
      timeout: nil,
      raise_error_responses: nil,
      callback_args: nil
    )
      self.class.async_request(
        method,
        url,
        callback: callback,
        headers: headers,
        body: body,
        json: json,
        params: params,
        timeout: timeout,
        raise_error_responses: raise_error_responses,
        callback_args: callback_args
      )
    end

    include HttpMethodHelpers
  end
end
