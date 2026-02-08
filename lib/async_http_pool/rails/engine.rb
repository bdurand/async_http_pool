# frozen_string_literal: true

# This file must be explicitly required to enable Rails integration.
# Usage: require "async_http_pool/rails/engine"
#
# This will allow you to install migrations using:
#   rails async_http_pool:install:migrations

require "rails/engine"

module AsyncHttpPool
  module Rails
    class Engine < ::Rails::Engine
      engine_name "async_http_pool"

      # Migrations will be picked up automatically from db/migrate
      # when the engine is loaded. Users can copy them using:
      #   rails async_http_pool:install:migrations
    end
  end
end
