# frozen_string_literal: true

class Document < ApplicationRecord
  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :uploaded_by_company_user, class_name: "CompanyUser", optional: true
  has_many :document_chunks, dependent: :destroy

  SOURCES = %w[whatsapp_upload company_portal_upload admin_upload].freeze
  STATUSES = %w[pending processing ready failed].freeze

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :filename, :storage_key, presence: true
end
