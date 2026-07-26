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
      company_id = @document.company_id
      orphan_knowledge_entries!
      Documents::StaleClarificationQuestions.for_document!(document: @document)
      @document.update!(
        status: "failed",
        purged_at: Time.current,
        processing_error: "purged",
        storage_key: "purged/#{@document.id}",
        insights_preview: {},
        metadata: (@document.metadata || {}).merge("purged" => true)
      )
      AggregateIntelligenceJob.perform_later(company_id)
      @document
    end

    private

    def orphan_knowledge_entries!
      CompanyKnowledgeEntry
        .where(company_id: @document.company_id, status: "active")
        .where("source_document_ids @> ARRAY[?]::bigint[]", @document.id)
        .find_each do |entry|
          sources = Array(entry.source_document_ids).map(&:to_i) - [@document.id]
          if sources.empty?
            entry.update!(status: "orphaned", source_document_ids: [])
          else
            entry.update!(source_document_ids: sources)
          end
        end
    end
  end
end
