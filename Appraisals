# frozen_string_literal: true

appraise "redis_5.0" do
  gem "redis", "~> 5.0.0"
end

appraise "without_payload_store_gems" do
  remove_gem "activerecord"
  remove_gem "sqlite3"
  remove_gem "aws-sdk-s3"
  remove_gem "redis"
end

appraise "activerecord_8.0" do
  gem "activerecord", "~> 8.0.0"
end

appraise "activerecord_7.2" do
  gem "activerecord", "~> 7.2.0"
  gem "sqlite3", "~> 1.4"
end

appraise "redis_5" do
  gem "redis", "~> 5.0.0"
end
