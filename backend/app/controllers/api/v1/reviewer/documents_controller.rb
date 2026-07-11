# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class DocumentsController < BaseController
        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize Document, :index?
          documents = policy_scope(Document).where(company_id: company.id).order(created_at: :desc).limit(100)
          render json: { documents: documents.map { |d| document_json(d) } }
        end

        def show
          document = find_document!
          authorize document, :show?
          render json: { document: document_json(document) }
        end

        def download
          document = find_document!
          authorize document, :download?
          data = Storage::MinioClient.new.download(document.storage_key)
          send_data data,
                    filename: document.filename,
                    type: document.content_type || "application/octet-stream",
                    disposition: "attachment"
        end

        private

        def find_document!
          company = policy_scope(::Company).find(params[:company_id])
          policy_scope(Document).where(company_id: company.id).find(params[:id])
        end

        def document_json(document)
          {
            id: document.id,
            filename: document.filename,
            department: document.department,
            document_type: document.try(:document_type),
            sensitivity: document.try(:sensitivity),
            reviewer_visible: document.try(:reviewer_visible),
            source: document.source,
            status: document.status,
            content_type: document.content_type,
            byte_size: document.byte_size,
            insights_preview: document.insights_preview,
            processing_error: document.processing_error,
            created_at: document.created_at,
            updated_at: document.updated_at
          }
        end
      end
    end
  end
end
