# frozen_string_literal: true

class TestService
  include AsyncHttpPool::RequestHelper

  request_template base_url: "https://api.example.com", headers: {"Authorization" => "Bearer token"}
end
