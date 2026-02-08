# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "async/http/server"
require "protocol/rack"
require "json"
require "net/http"
require "uri"
require "console"

class TestWebServer
  def initialize
    @thread = nil
    @port = nil
    @shutdown = false
    @ready = false
  end

  def start(port = nil)
    return self if @thread&.alive?

    port = find_free_port if port.nil? || port.zero?
    @port = port
    @thread = Thread.new { run_server }
    self
  end

  def ready?(timeout: 5.0)
    unless @ready
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        if server_ready?
          @ready = true
          break
        end
        sleep 0.01
      end
    end

    @ready
  end

  def stop
    @shutdown = true
    @thread&.kill
    @thread&.join(1)
  end

  def base_url
    "http://localhost:#{@port}"
  end

  private

  def find_free_port
    server = TCPServer.new("localhost", 0)
    port = server.addr[1]
    server.close
    port
  end

  def run_server
    # Suppress warnings from the Async HTTP server during tests
    Console.logger.level = Logger::ERROR

    # Wrap Rack app for async HTTP server
    rack_app = build_app
    app = Protocol::Rack::Adapter.new(rack_app)

    # Create endpoint
    endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{@port}")

    # Start async HTTP server
    Async do |task|
      server = Async::HTTP::Server.new(app, endpoint)
      server_task = task.async do
        server.run
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        # Silently ignore broken pipe and connection errors
        # These occur when clients disconnect early (e.g., during size limit tests)
      end

      # Monitor for shutdown
      task.async do
        loop do
          break if @shutdown
          sleep 0.1
        end
        server_task.stop
      end

      server_task.wait
    end
  end

  def build_app
    lambda do |env|
      path = env["PATH_INFO"]

      if path == "/health"
        [200, {"Content-Type" => "text/plain"}, ["OK"]]
      elsif path.match?(%r{\A/test/\d+\z})
        test_response(env)
      elsif (match = path.match(%r{\A/delay/(\d+)\z}))
        delay = match[1].to_f / 1000.0
        delay_response(delay)
      else
        [404, {"Content-Type" => "text/plain"}, ["404 page not found\n"]]
      end
    end
  end

  def health_check_response
    [200, {"Content-Type" => "text/plain"}, ["OK"]]
  end

  def test_response(env)
    path = env["PATH_INFO"]
    query_string = env["QUERY_STRING"] || ""
    headers = extract_headers(env)

    # Ensure request body is fully consumed before sending response
    # This is important for POST/PUT requests with bodies
    body = read_body(env)

    status_code = path.sub(%r{\A/test/}, "").to_i

    response_body = JSON.generate({
      status: status_code,
      body: body,
      headers: headers,
      query_string: query_string
    })

    [
      status_code,
      {
        "Content-Type" => "application/json",
        "Content-Length" => response_body.bytesize.to_s
      },
      [response_body]
    ]
  end

  def delay_response(delay)
    # Create a streaming body that sends chunks with delays between them
    # This simulates a slow-streaming server response
    [200, {"Content-Type" => "application/json"}, StreamingBody.new(delay)]
  end

  # Rack-compatible streaming body
  class StreamingBody
    def initialize(delay)
      @delay = delay
    end

    def each
      # Split the delay across multiple chunks
      chunk_count = 5
      chunk_delay = @delay / chunk_count

      chunk_count.times do |i|
        sleep(chunk_delay)
        yield JSON.generate({chunk: i, delay: chunk_delay})
        yield "\n"
      end
    end
  end

  def extract_headers(env)
    headers = {}

    # Extract HTTP_* headers
    env.each do |key, value|
      if key.start_with?("HTTP_")
        header_name = key.sub(/^HTTP_/, "").downcase.tr("_", "-")
        headers[header_name] = value
      end
    end

    # Rack stores some headers without HTTP_ prefix
    headers["content-type"] = env["CONTENT_TYPE"] if env["CONTENT_TYPE"]
    headers["content-length"] = env["CONTENT_LENGTH"] if env["CONTENT_LENGTH"]

    headers
  end

  def read_body(env)
    input = env["rack.input"]
    return "" unless input

    # Read and return the entire body
    body = input.read

    # Rewind the input stream in case it needs to be read again
    input.rewind if input.respond_to?(:rewind)
    body || ""
  end

  def server_ready?
    uri = URI("#{base_url}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 0.1
    http.read_timeout = 0.1
    begin
      response = http.get(uri.path)
      response.is_a?(Net::HTTPSuccess)
    ensure
      http.finish if http.started?
    end
  rescue
    false
  end
end
