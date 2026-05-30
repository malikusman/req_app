# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class DocumentsController < BaseController
        include CompanyPortalDocumentJson

        def index
          company = policy_scope(::Company).find(params[:company_id])
          authorize company, :show?

          documents = policy_scope(Document)
                        .where(company_id: company.id, source: "company_portal_upload")
                        .order(created_at: :desc)
                        .limit(100)

          render json: { documents: documents.map { |d| company_portal_document_json(d) } }
        end

        def download
          company = policy_scope(::Company).find(params[:company_id])
          document = company.documents.find(params[:id])
          authorize document, :download?

          data = Storage::MinioClient.new.download(document.storage_key)
          send_data data,
                    type: document.content_type.presence || "application/octet-stream",
                    filename: document.filename,
                    disposition: "attachment"
        rescue Aws::S3::Errors::NoSuchKey
          head :not_found
        end
      end
    end
  end
end
