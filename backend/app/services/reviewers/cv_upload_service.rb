# frozen_string_literal: true

module Reviewers
  class CvUploadService
    ALLOWED = [
      "application/pdf",
      "application/msword",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ].freeze

    def self.call(reviewer:, file:)
      new(reviewer: reviewer, file: file).call
    end

    def initialize(reviewer:, file:)
      @reviewer = reviewer
      @file = file
    end

    def call
      raise ArgumentError, "CV file required" unless @file.respond_to?(:read)

      content_type = @file.content_type.to_s
      raise ArgumentError, "Only PDF or Word CV files are allowed" unless ALLOWED.include?(content_type)

      filename = @file.original_filename.presence || "cv"
      body = @file.read
      key = "reviewers/#{@reviewer.id}/cv/#{SecureRandom.uuid}/#{filename}"
      Storage::MinioClient.new.upload(key: key, body: body, content_type: content_type)

      @reviewer.update!(
        cv_storage_key: key,
        cv_filename: filename,
        cv_content_type: content_type,
        cv_byte_size: body.bytesize
      )
    end
  end
end
