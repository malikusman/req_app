# frozen_string_literal: true

module Reviewers
  class AvatarUploadService
    ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    MAX_BYTES = 5.megabytes

    def self.call(reviewer:, file:)
      new(reviewer: reviewer, file: file).call
    end

    def initialize(reviewer:, file:)
      @reviewer = reviewer
      @file = file
    end

    def call
      raise ArgumentError, "file required" unless @file.respond_to?(:read)

      content_type = @file.content_type.to_s
      unless ALLOWED_TYPES.include?(content_type)
        raise ArgumentError, "unsupported image type"
      end

      body = @file.read
      raise ArgumentError, "file too large" if body.bytesize > MAX_BYTES

      ext = content_type.split("/").last.gsub("jpeg", "jpg")
      key = "reviewers/#{@reviewer.id}/avatar/#{SecureRandom.uuid}.#{ext}"

      if @reviewer.avatar_storage_key.present?
        Storage::MinioClient.new.delete(@reviewer.avatar_storage_key)
      end

      Storage::MinioClient.new.upload(key: key, body: body, content_type: content_type)
      @reviewer.update!(avatar_storage_key: key)
      key
    end
  end
end
