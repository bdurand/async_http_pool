# frozen_string_literal: true

require "async"
require "async/http"
require "concurrent"
require "json"
require "uri"
require "zlib"
require "time"
require "socket"
require "securerandom"
require "logger"

# Generic async HTTP connection pool for Ruby applications.
#
# This module provides:
# - Async HTTP request processing using Ruby's Fiber scheduler
# - Connection pooling with HTTP/2 support
# - Configurable timeouts, retries, and proxy support
# - Error handling with typed errors
#
# This module can be used standalone or integrated with job systems
# like Sidekiq via adapters.
module AsyncHttpPool
  # Raised when trying to enqueue a request when the processor is not running
  class NotRunningError < StandardError; end

  class MaxCapacityError < StandardError; end

  class ResponseTooLargeError < StandardError; end

  VERSION = File.read(File.join(__dir__, "../VERSION")).strip

  # Autoload utility modules
  autoload :ClassHelper, File.join(__dir__, "async_http_pool/class_helper")
  autoload :TimeHelper, File.join(__dir__, "async_http_pool/time_helper")

  # Autoload all components
  autoload :CallbackArgs, File.join(__dir__, "async_http_pool/callback_args")
  autoload :CallbackValidator, File.join(__dir__, "async_http_pool/callback_validator")
  autoload :Client, File.join(__dir__, "async_http_pool/client")
  autoload :ClientError, File.join(__dir__, "async_http_pool/http_error")
  autoload :ClientPool, File.join(__dir__, "async_http_pool/client_pool")
  autoload :Configuration, File.join(__dir__, "async_http_pool/configuration")
  autoload :Error, File.join(__dir__, "async_http_pool/error")
  autoload :ExternalStorage, File.join(__dir__, "async_http_pool/external_storage")
  autoload :HttpError, File.join(__dir__, "async_http_pool/http_error")
  autoload :HttpHeaders, File.join(__dir__, "async_http_pool/http_headers")
  autoload :LifecycleManager, File.join(__dir__, "async_http_pool/lifecycle_manager")
  autoload :Payload, File.join(__dir__, "async_http_pool/payload")
  autoload :PayloadStore, File.join(__dir__, "async_http_pool/payload_store")
  autoload :Processor, File.join(__dir__, "async_http_pool/processor")
  autoload :ProcessorObserver, File.join(__dir__, "async_http_pool/processor_observer")
  autoload :RecursiveRedirectError, File.join(__dir__, "async_http_pool/redirect_error")
  autoload :RedirectError, File.join(__dir__, "async_http_pool/redirect_error")
  autoload :Request, File.join(__dir__, "async_http_pool/request")
  autoload :RequestError, File.join(__dir__, "async_http_pool/request_error")
  autoload :RequestTask, File.join(__dir__, "async_http_pool/request_task")
  autoload :RequestTemplate, File.join(__dir__, "async_http_pool/request_template")
  autoload :Response, File.join(__dir__, "async_http_pool/response")
  autoload :ResponseReader, File.join(__dir__, "async_http_pool/response_reader")
  autoload :ServerError, File.join(__dir__, "async_http_pool/http_error")
  autoload :SynchronousExecutor, File.join(__dir__, "async_http_pool/synchronous_executor")
  autoload :TaskHandler, File.join(__dir__, "async_http_pool/task_handler")
  autoload :TooManyRedirectsError, File.join(__dir__, "async_http_pool/redirect_error")

  @testing = false

  class << self
    # Check if running in testing mode.
    #
    # @api private
    def testing?
      @testing
    end

    # Set testing mode.
    #
    # @api private
    def testing=(value)
      @testing = !!value
    end
  end
end
