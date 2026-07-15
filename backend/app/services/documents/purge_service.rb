# frozen_string_literal: true

module Documents
  class PurgeService
    def self.call(document:)
      new(document: document).call
    end

    def initialize(document:)
      @document = document
    end

    def call
      Storage::MinioClient.new.delete(@document.storage_key) if @document.storage_key.present?
      @document.document_chunks.delete_all
      @document.update!(
        status: "failed",
        purged_at: Time.current,
        processing_error: "purged",
        storage_key: "purged/#{@document.id}",
        insights_preview: {},
        metadata: (@document.metadata || {}).merge("purged" => true)
      )
      @document
    end
  end
end
