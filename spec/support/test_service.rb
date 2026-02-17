# frozen_string_literal: true

class TestService
  include PatientHttp::RequestHelper

  request_template base_url: "https://api.example.com", headers: {"Authorization" => "Bearer token"}
end
