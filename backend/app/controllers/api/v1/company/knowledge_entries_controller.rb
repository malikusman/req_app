# frozen_string_literal: true

module Api
  module V1
    module Company
      class KnowledgeEntriesController < BaseController
        def index
          authorize CompanyKnowledgeEntry, :index?
          entries = policy_scope(CompanyKnowledgeEntry).active.order(updated_at: :desc).limit(200)
          render json: { knowledge_entries: entries.map { |e| entry_json(e) } }
        end

        private

        def entry_json(entry)
          {
            id: entry.id,
            entry_type: entry.entry_type,
            title: entry.title,
            content: entry.content,
            confidence: entry.confidence,
            department: entry.department,
            status: entry.status,
            source_document_ids: entry.source_document_ids,
            analysis_run_id: entry.document_analysis_run_id,
            created_at: entry.created_at,
            updated_at: entry.updated_at
          }
        end
      end
    end
  end
end
