# frozen_string_literal: true

class MediaAttachment < ApplicationRecord
  belongs_to :message
  belongs_to :company
  belongs_to :employee
  belongs_to :conversation
  belongs_to :document, optional: true

  TYPES = %w[audio image document].freeze
  STATUSES = %w[pending processing ready failed].freeze

  validates :attachment_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
end
