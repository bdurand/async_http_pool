# frozen_string_literal: true

# S3/Minio test helpers
#
# This helper provides access to a Minio-based S3 bucket for testing.
# Requires the minio docker container to be running on port 24456.

module S3Helper
  MINIO_ENDPOINT = ENV.fetch("MINIO_ENDPOINT", "http://127.0.0.1:24456")
  MINIO_ACCESS_KEY = ENV.fetch("MINIO_ACCESS_KEY", "minioadmin")
  MINIO_SECRET_KEY = ENV.fetch("MINIO_SECRET_KEY", "minioadmin")
  TEST_BUCKET_NAME = ENV.fetch("S3_TEST_BUCKET", "test-payloads")

  class << self
    def available?
      @available ||= begin
        require "aws-sdk-s3"
        true
      rescue LoadError
        false
      end
    end

    def setup
      S3Helper.ensure_bucket_exists if available?
    end

    def s3_client
      @s3_client ||= begin
        require "aws-sdk-s3"
        Aws::S3::Client.new(
          endpoint: MINIO_ENDPOINT,
          access_key_id: MINIO_ACCESS_KEY,
          secret_access_key: MINIO_SECRET_KEY,
          region: "us-east-1",
          force_path_style: true
        )
      end
    end

    def s3_resource
      @s3_resource ||= begin
        require "aws-sdk-s3"
        Aws::S3::Resource.new(client: s3_client)
      end
    end

    def test_bucket
      s3_resource.bucket(TEST_BUCKET_NAME)
    end

    def ensure_bucket_exists
      s3_client.head_bucket(bucket: TEST_BUCKET_NAME)
    rescue Aws::S3::Errors::NotFound
      s3_client.create_bucket(bucket: TEST_BUCKET_NAME)
    end

    def clear_bucket
      test_bucket.objects.batch_delete!
    rescue Aws::S3::Errors::NoSuchBucket
      # Bucket doesn't exist, nothing to clear
    end

    def reset!
      @s3_client = nil
      @s3_resource = nil
    end
  end
end
