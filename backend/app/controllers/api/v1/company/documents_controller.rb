# frozen_string_literal: true

module Api
  module V1
    module Company
      class DocumentsController < BaseController
        include CompanyPortalDocumentJson

        skip_before_action :require_active_subscription!

        ALLOWED_EXTENSIONS = %w[.pdf .docx .pptx .txt .md .csv].freeze
        ALLOWED_CONTENT_TYPES = [
          "application/pdf",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "application/vnd.openxmlformats-officedocument.presentationml.presentation",
          "text/plain",
          "text/markdown",
          "text/csv"
        ].freeze
        MAX_UPLOAD_BYTES = 10.megabytes

        def index
          authorize Document, :index?
          documents = policy_scope(Document).order(created_at: :desc).limit(50)
          render json: { documents: documents.map { |d| company_portal_document_json(d) } }
        end

        def create
          authorize Document, :create?
          file = params[:file]
          return render json: { error: "file required" }, status: :unprocessable_entity unless file.respond_to?(:read)

          filename = file.original_filename.presence || "upload.bin"
          content_type = file.content_type
          extension = File.extname(filename).downcase
          unless allowed_upload?(content_type: content_type, extension: extension)
            return render json: { error: "Unsupported file type. Allowed: PDF, DOCX, PPTX, TXT, MD, CSV" },
                          status: :unprocessable_entity
          end

          storage_key = "documents/#{current_company.id}/#{SecureRandom.uuid}/#{filename}"
          body = file.read
          if body.bytesize > MAX_UPLOAD_BYTES
            return render json: { error: "File exceeds maximum size of 10MB" }, status: :unprocessable_entity
          end

          Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: content_type)

          category = params[:category].presence
          if category.present? && !Companies::ProfileContextSchema::DOCUMENT_CATEGORIES.include?(category)
            return render json: { error: "Invalid document category" }, status: :unprocessable_entity
          end

          admin_description = params[:admin_description].to_s.strip.truncate(500)
          upload_metadata = {
            "category" => category,
            "admin_description" => admin_description.presence,
            "upload_context" => params[:upload_context].presence || "documents"
          }.compact

          document = current_company.documents.create!(
            uploaded_by_company_user: current_company_user,
            source: "company_portal_upload",
            department: params[:department].presence,
            filename: filename,
            content_type: content_type,
            byte_size: body.bytesize,
            storage_key: storage_key,
            status: "pending",
            metadata: upload_metadata
          )

          ParseDocumentJob.perform_later(document.id)
          render json: { document: company_portal_document_json(document) }, status: :created
        end

        def download
          document = policy_scope(Document).find(params[:id])
          authorize document, :download?

          data = Storage::MinioClient.new.download(document.storage_key)
          send_data data,
                    type: document.content_type.presence || "application/octet-stream",
                    filename: document.filename,
                    disposition: "attachment"
        rescue Aws::S3::Errors::NoSuchKey
          head :not_found
        end

        private

        def allowed_upload?(content_type:, extension:)
          ALLOWED_EXTENSIONS.include?(extension) || ALLOWED_CONTENT_TYPES.include?(content_type.to_s.downcase)
        end
      end
    end
  end
end
