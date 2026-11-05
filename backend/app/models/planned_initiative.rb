# frozen_string_literal: true

# A change already planned — a new system, a restructure, hiring, outsourcing
# (Doc 06 §5.3) — so later stages never recommend work it would make obsolete.
class PlannedInitiative < ApplicationRecord
  TYPES = %w[ERP CRM SYSTEM_REPLACEMENT RESTRUCTURE HIRING OUTSOURCING DIGITISATION POLICY_CHANGE OTHER].freeze
  STATUSES = %w[CONFIRMED PROPOSED UNCERTAIN].freeze

  belongs_to :company
  belongs_to :engagement
  belongs_to :management_discovery_context

  validates :initiative_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :description, presence: true
end
