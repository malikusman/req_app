# frozen_string_literal: true

module Api
  module V1
    module Company
      class DocumentsController < BaseController
        def index
          authorize Document, :index?
          documents = policy_scope(Document).order(created_at: :desc).limit(50)
          render json: { documents: documents.map { |d| document_json(d) } }
        end

        def create
          authorize Document, :create?
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          filename = file.original_filename.presence || "upload.bin"
          content_type = file.content_type
          storage_key = "documents/#{current_company.id}/#{SecureRandom.uuid}/#{filename}"
          body = file.read

          Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: content_type)

          document = current_company.documents.create!(
            uploaded_by_company_user: current_company_user,
            source: "company_portal_upload",
            department: params[:department].presence,
            filename: filename,
            content_type: content_type,
            byte_size: body.bytesize,
            storage_key: storage_key,
            status: "pending"
          )

          ParseDocumentJob.perform_later(document.id)
          render json: { document: document_json(document) }, status: :created
        end

        private

        def document_json(document)
          {
            id: document.id,
            filename: document.filename,
            department: document.department,
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
