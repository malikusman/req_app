# frozen_string_literal: true

class Document < ApplicationRecord
  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :uploaded_by_company_user, class_name: "CompanyUser", optional: true
  has_many :document_chunks, dependent: :destroy

  SOURCES = %w[whatsapp_upload company_portal_upload admin_upload web_upload].freeze
  STATUSES = %w[pending processing ready failed].freeze
  DOCUMENT_TYPES = %w[sop org_chart policy process other].freeze
  SENSITIVITIES = %w[internal confidential restricted].freeze

  ALLOWED_CONTENT_TYPES = {
    "application/pdf" => %w[.pdf],
    "text/plain" => %w[.txt],
    "text/markdown" => %w[.md],
    "text/csv" => %w[.csv],
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => %w[.docx],
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => %w[.xlsx],
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => %w[.pptx],
    "image/jpeg" => %w[.jpg .jpeg],
    "image/png" => %w[.png],
    "image/webp" => %w[.webp]
  }.freeze

  MAX_BYTES = 25.megabytes

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :filename, :storage_key, presence: true
  validates :document_type, inclusion: { in: DOCUMENT_TYPES }, allow_nil: true
  validates :sensitivity, inclusion: { in: SENSITIVITIES }, allow_nil: true

  scope :ready, -> { where(status: "ready") }
  scope :portal, -> { where(source: "company_portal_upload") }
  scope :reviewer_visible, -> { where(reviewer_visible: true) }

  def self.allowed_content_type?(content_type)
    ALLOWED_CONTENT_TYPES.key?(content_type.to_s)
  end
end
