# frozen_string_literal: true

require "aws-sdk-s3"

module Storage
  class MinioClient
    BUCKET = ENV.fetch("MINIO_BUCKET", "req-app").freeze

    def initialize
      @client = Aws::S3::Client.new(
        access_key_id: ENV.fetch("MINIO_ACCESS_KEY", "minioadmin"),
        secret_access_key: ENV.fetch("MINIO_SECRET_KEY", "minioadmin"),
        endpoint: ENV.fetch("MINIO_ENDPOINT", "http://minio:9000"),
        region: ENV.fetch("MINIO_REGION", "us-east-1"),
        force_path_style: true
      )
      ensure_bucket!
    end

    def upload(key:, body:, content_type: nil)
      @client.put_object(
        bucket: BUCKET,
        key: key,
        body: body,
        content_type: content_type
      )
      key
    end

    def download(key)
      response = @client.get_object(bucket: BUCKET, key: key)
      response.body.read
    end

    def delete(key)
      @client.delete_object(bucket: BUCKET, key: key)
    rescue Aws::S3::Errors::ServiceError
      nil
    end

    private

    def ensure_bucket!
      @client.head_bucket(bucket: BUCKET)
    rescue Aws::S3::Errors::NotFound
      @client.create_bucket(bucket: BUCKET)
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.warn("[MinIO] bucket check skipped: #{e.message}")
    end
  end
end
