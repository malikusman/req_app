# frozen_string_literal: true

class Document < ApplicationRecord
  belongs_to :company
  belongs_to :employee, optional: true
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :uploaded_by_company_user, class_name: "CompanyUser", optional: true
  belongs_to :document_request, optional: true
  has_many :document_chunks, dependent: :destroy

  # key_person_upload: shared in a conversation with leadership. Management's own
  # material (KPI packs, reports, strategy) is never ingested, chunked or marked
  # ready — the employee interview reads every ready chunk — and the client
  # portal doesn't list it, so one manager never sees another's (Doc 14 §9.2).
  # Consultants see it.
  LEADERSHIP_SOURCE = "key_person_upload"
  SOURCES = (%w[whatsapp_upload company_portal_upload admin_upload web_upload] + [LEADERSHIP_SOURCE]).freeze
  STATUSES = %w[uploaded pending processing ready failed].freeze
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
  scope :uploaded, -> { where(status: "uploaded") }
  scope :awaiting_analysis, -> { where(status: %w[uploaded failed]) }
  scope :portal, -> { where(source: "company_portal_upload") }
  scope :leadership, -> { where(source: LEADERSHIP_SOURCE) }
  scope :not_leadership, -> { where.not(source: LEADERSHIP_SOURCE) }
  scope :consultant_visible, -> { where(consultant_visible: true) }

  def self.allowed_content_type?(content_type)
    ALLOWED_CONTENT_TYPES.key?(content_type.to_s)
  end
end
