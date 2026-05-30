# frozen_string_literal: true

module CompanyPortalDocumentJson
  extend ActiveSupport::Concern

  private

  def company_portal_document_json(document)
    meta = document.metadata || {}
    {
      id: document.id,
      filename: document.filename,
      department: document.department,
      source: document.source,
      status: document.status,
      content_type: document.content_type,
      byte_size: document.byte_size,
      category: meta["category"],
      admin_description: meta["admin_description"],
      insights_preview: document.insights_preview,
      processing_error: document.processing_error,
      created_at: document.created_at,
      updated_at: document.updated_at
    }
  end
end
