# frozen_string_literal: true

require "spec_helper"

RSpec.describe PatientHttp::Error do
  describe ".load" do
    it "dispatches to HttpError for response errors" do
      response = PatientHttp::Response.new(
        status: 404,
        headers: {"Content-Type" => "text/plain"},
        body: "Not Found",
        duration: 0.1,
        request_id: "test-request",
        url: "https://example.com",
        http_method: :get
      )

      hash = {"response" => response.as_json}
      error = described_class.load(hash)

      expect(error).to be_a(PatientHttp::HttpError)
    end

    it "dispatches to RedirectError for redirect errors" do
      hash = {
        "error_class" => PatientHttp::TooManyRedirectsError.name,
        "url" => "https://example.com",
        "http_method" => "get",
        "duration" => 1.0,
        "request_id" => "req-1",
        "redirects" => ["https://example.com/1"]
      }

      error = described_class.load(hash)

      expect(error).to be_a(PatientHttp::TooManyRedirectsError)
    end

    it "dispatches to RequestError for request errors" do
      hash = {
        "class_name" => "StandardError",
        "message" => "Test error",
        "backtrace" => [],
        "request_id" => "req-123",
        "error_type" => "timeout",
        "duration" => 1.0,
        "url" => "https://example.com",
        "http_method" => "get"
      }

      error = described_class.load(hash)

      expect(error).to be_a(PatientHttp::RequestError)
    end
  end
end
