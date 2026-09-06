# frozen_string_literal: true

module Consultants
  class CvUploadService
    ALLOWED_TYPES = %w[application/pdf].freeze
    MAX_BYTES = 10.megabytes

    def self.call(consultant:, file:)
      new(consultant: consultant, file: file).call
    end

    def initialize(consultant:, file:)
      @consultant = consultant
      @file = file
    end

    def call
      raise ArgumentError, "file required" unless @file.respond_to?(:read)

      content_type = @file.content_type.to_s
      unless ALLOWED_TYPES.include?(content_type) || @file.original_filename.to_s.downcase.end_with?(".pdf")
        raise ArgumentError, "CV must be a PDF"
      end

      body = @file.read
      raise ArgumentError, "file too large (max 10MB)" if body.bytesize > MAX_BYTES

      key = "consultants/#{@consultant.id}/cv/#{SecureRandom.uuid}.pdf"

      if @consultant.cv_storage_key.present?
        begin
          Storage::MinioClient.new.delete(@consultant.cv_storage_key)
        rescue StandardError
          nil
        end
      end

      Storage::MinioClient.new.upload(key: key, body: body, content_type: "application/pdf")
      @consultant.update!(cv_storage_key: key)
      answers = (@consultant.questionnaire_answers || {}).merge("cv_upload" => true)
      @consultant.update!(questionnaire_answers: answers)
      key
    end
  end
end
