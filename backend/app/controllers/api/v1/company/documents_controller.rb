# frozen_string_literal: true

module Api
  module V1
    module Company
      class DocumentsController < BaseController
        def index
          authorize Document, :index?
          documents = policy_scope(Document)
            .where(purged_at: nil)
            .order(updated_at: :desc)
            .limit(100)
          render json: { documents: documents.map { |d| document_json(d) } }
        end

        def show
          document = policy_scope(Document).find(params[:id])
          authorize document, :show?
          render json: { document: document_json(document) }
        end

        def create
          authorize Document, :create?
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          filename = file.original_filename.presence || "upload.bin"
          content_type = file.content_type.to_s
          body = file.read

          unless Document.allowed_content_type?(content_type)
            return render json: { error: "unsupported file type; allowed: PDF, TXT, MD, CSV, DOCX, XLSX, PPTX, images" },
                          status: :unprocessable_entity
          end
          if body.bytesize > Document::MAX_BYTES
            return render json: { error: "file too large (max #{Document::MAX_BYTES / 1.megabyte}MB)" },
                          status: :unprocessable_entity
          end

          storage_key = "documents/#{current_company.id}/#{SecureRandom.uuid}/#{filename}"
          Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: content_type)

          document = current_company.documents.create!(
            uploaded_by_company_user: current_company_user,
            source: "company_portal_upload",
            department: params[:department].presence,
            document_type: params[:document_type].presence || "other",
            sensitivity: params[:sensitivity].presence || "internal",
            reviewer_visible: params[:reviewer_visible] != "false",
            filename: filename,
            content_type: content_type,
            byte_size: body.bytesize,
            storage_key: storage_key,
            status: "uploaded",
            retained_until: retention_until_from(params[:retention_days]),
            metadata: {
              "uploaded_by" => current_company_user.id,
              "retention_days" => params[:retention_days].presence&.to_i
            }
          )

          render json: { document: document_json(document) }, status: :created
        end

        def replace
          document = policy_scope(Document).find(params[:id])
          authorize document, :update?
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          filename = file.original_filename.presence || document.filename
          content_type = file.content_type.to_s
          body = file.read
          unless Document.allowed_content_type?(content_type)
            return render json: { error: "unsupported file type" }, status: :unprocessable_entity
          end
          if body.bytesize > Document::MAX_BYTES
            return render json: { error: "file too large" }, status: :unprocessable_entity
          end

          storage_key = "documents/#{current_company.id}/#{SecureRandom.uuid}/#{filename}"
          Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: content_type)
          document.document_chunks.delete_all
          current_company.company_knowledge_entries.active
            .where("? = ANY(source_document_ids)", document.id)
            .update_all(status: "superseded") # rubocop:disable Rails/SkipsModelValidations
          Documents::StaleClarificationQuestions.for_document!(document: document)

          document.update!(
            filename: filename,
            content_type: content_type,
            byte_size: body.bytesize,
            storage_key: storage_key,
            status: "uploaded",
            processing_error: nil,
            insights_preview: {},
            version_number: document.version_number.to_i + 1,
            metadata: (document.metadata || {}).except("content_sha256")
          )
          render json: { document: document_json(document) }
        end

        def update
          document = policy_scope(Document).find(params[:id])
          authorize document, :update?

          attrs = {}
          if params.key?(:reviewer_visible)
            attrs[:reviewer_visible] = ActiveModel::Type::Boolean.new.cast(params[:reviewer_visible])
          end
          attrs[:department] = params[:department].presence if params.key?(:department)

          document.update!(attrs) if attrs.any?
          render json: { document: document_json(document) }
        end

        def download
          document = policy_scope(Document).find(params[:id])
          authorize document, :download?
          data = Storage::MinioClient.new.download(document.storage_key)
          send_data data, filename: document.filename, type: document.content_type || "application/octet-stream",
                          disposition: "attachment"
        end

        def destroy
          document = policy_scope(Document).find(params[:id])
          authorize document, :destroy?
          Documents::PurgeService.call(document: document)
          head :no_content
        end

        private

        def retention_until_from(days)
          n = days.to_i
          return nil unless n.positive?

          n.days.from_now
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
