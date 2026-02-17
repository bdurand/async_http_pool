# frozen_string_literal: true

require "spec_helper"

RSpec.describe PatientHttp::HttpError do
  describe ".new factory" do
    it "returns HttpError for non-4xx/5xx status" do
      response = PatientHttp::Response.new(
        status: 301,
        headers: {"Location" => "https://example.com/new"},
        body: "",
        duration: 0.1,
        request_id: "test-301",
        url: "https://example.com",
        http_method: :get
      )

      error = described_class.new(response)

      expect(error.class).to eq(PatientHttp::HttpError)
      expect(error).not_to be_a(PatientHttp::ClientError)
      expect(error).not_to be_a(PatientHttp::ServerError)
    end
  end

  describe "#error_type" do
    it "returns :http_error" do
      response = PatientHttp::Response.new(
        status: 404,
        headers: {},
        body: "",
        duration: 0.1,
        request_id: "test",
        url: "https://example.com",
        http_method: :get
      )

      error = described_class.new(response)

      expect(error.error_type).to eq(:http_error)
    end
  end

  describe "#error_class" do
    it "returns self.class" do
      response = PatientHttp::Response.new(
        status: 404,
        headers: {},
        body: "",
        duration: 0.1,
        request_id: "test",
        url: "https://example.com",
        http_method: :get
      )

      error = described_class.new(response)

      expect(error.error_class).to eq(PatientHttp::ClientError)
    end
  end
end

RSpec.describe PatientHttp::ClientError do
  describe "factory pattern" do
    it "returns ClientError for 4xx responses" do
      response = PatientHttp::Response.new(
        status: 404,
        headers: {"Content-Type" => "text/plain"},
        body: "Not Found",
        duration: 0.1,
        request_id: "test-request",
        url: "https://example.com",
        http_method: :get
      )

      error = PatientHttp::HttpError.new(response)

      expect(error).to be_a(PatientHttp::ClientError)
      expect(error).to be_a(PatientHttp::HttpError)
      expect(error.status).to eq(404)
      expect(error.message).to eq("HTTP 404 response from GET https://example.com")
    end

    it "inherits all HttpError behavior" do
      response = PatientHttp::Response.new(
        status: 400,
        headers: {"Content-Type" => "application/json"},
        body: '{"error":"Bad Request"}',
        duration: 0.05,
        request_id: "test-400",
        url: "https://api.example.com/endpoint",
        http_method: :post
      )

      error = PatientHttp::HttpError.new(response)

      expect(error.status).to eq(400)
      expect(error.url).to eq("https://api.example.com/endpoint")
      expect(error.http_method).to eq(:post)
      expect(error.duration).to eq(0.05)
      expect(error.request_id).to eq("test-400")
      expect(error.response).to eq(response)
    end
  end

  describe "serialization" do
    it "round-trips through JSON as ClientError" do
      response = PatientHttp::Response.new(
        status: 403,
        headers: {"Content-Type" => "text/plain"},
        body: "Forbidden",
        duration: 0.2,
        request_id: "test-403",
        url: "https://example.com/protected",
        http_method: :get,
        callback_args: {"user_id" => 123}
      )

      original_error = PatientHttp::HttpError.new(response)

      hash = original_error.as_json
      restored_error = PatientHttp::HttpError.load(hash)

      expect(restored_error).to be_a(PatientHttp::ClientError)
      expect(restored_error.status).to eq(original_error.status)
      expect(restored_error.url).to eq(original_error.url)
      expect(restored_error.http_method).to eq(original_error.http_method)
      expect(restored_error.duration).to eq(original_error.duration)
      expect(restored_error.request_id).to eq(original_error.request_id)
      expect(restored_error.message).to eq(original_error.message)
      expect(restored_error.response.body).to eq(original_error.response.body)
      expect(restored_error.response.headers.to_h).to eq(original_error.response.headers.to_h)
      expect(restored_error.callback_args.to_h).to eq(original_error.callback_args.to_h)
    end
  end
end

RSpec.describe PatientHttp::ServerError do
  describe "factory pattern" do
    it "returns ServerError for 5xx responses" do
      response = PatientHttp::Response.new(
        status: 500,
        headers: {"Content-Type" => "text/plain"},
        body: "Internal Server Error",
        duration: 0.3,
        request_id: "test-500",
        url: "https://example.com",
        http_method: :post
      )

      error = PatientHttp::HttpError.new(response)

      expect(error).to be_a(PatientHttp::ServerError)
      expect(error).to be_a(PatientHttp::HttpError)
      expect(error.status).to eq(500)
      expect(error.message).to eq("HTTP 500 response from POST https://example.com")
    end

    it "returns ServerError for 503 Service Unavailable" do
      response = PatientHttp::Response.new(
        status: 503,
        headers: {"Content-Type" => "text/plain"},
        body: "Service Unavailable",
        duration: 0.1,
        request_id: "test-503",
        url: "https://api.example.com",
        http_method: :get
      )

      error = PatientHttp::HttpError.new(response)

      expect(error).to be_a(PatientHttp::ServerError)
      expect(error.status).to eq(503)
    end

    it "inherits all HttpError behavior" do
      response = PatientHttp::Response.new(
        status: 502,
        headers: {"Content-Type" => "application/json"},
        body: '{"error":"Bad Gateway"}',
        duration: 0.15,
        request_id: "test-502",
        url: "https://api.example.com/endpoint",
        http_method: :put
      )

      error = PatientHttp::HttpError.new(response)

      expect(error.status).to eq(502)
      expect(error.url).to eq("https://api.example.com/endpoint")
      expect(error.http_method).to eq(:put)
      expect(error.duration).to eq(0.15)
      expect(error.request_id).to eq("test-502")
      expect(error.response).to eq(response)
    end
  end

  describe "serialization" do
    it "round-trips through JSON as ServerError" do
      response = PatientHttp::Response.new(
        status: 504,
        headers: {"Content-Type" => "text/plain"},
        body: "Gateway Timeout",
        duration: 30.0,
        request_id: "test-504",
        url: "https://slow.example.com/api",
        http_method: :post,
        callback_args: {"request_id" => "abc123"}
      )

      original_error = PatientHttp::HttpError.new(response)

      hash = original_error.as_json
      restored_error = PatientHttp::HttpError.load(hash)

      expect(restored_error).to be_a(PatientHttp::ServerError)
      expect(restored_error.status).to eq(original_error.status)
      expect(restored_error.url).to eq(original_error.url)
      expect(restored_error.http_method).to eq(original_error.http_method)
      expect(restored_error.duration).to eq(original_error.duration)
      expect(restored_error.request_id).to eq(original_error.request_id)
      expect(restored_error.message).to eq(original_error.message)
      expect(restored_error.response.body).to eq(original_error.response.body)
      expect(restored_error.response.headers.to_h).to eq(original_error.response.headers.to_h)
      expect(restored_error.callback_args.to_h).to eq(original_error.callback_args.to_h)
    end
  end
end
