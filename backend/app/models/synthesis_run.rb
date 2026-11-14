# frozen_string_literal: true

# One pass of consolidation and synthesis over an engagement (Doc 10 §5): what
# set it off, what it read, how it went, and P11's run-level output — the
# operating picture, initiative conflicts, role potential and coverage notes.
#
# Consultant-only. The operating picture reaches the client only once a
# consultant approves it, inside a released report (Doc 00 C11).
class SynthesisRun < ApplicationRecord
  # FINDINGS: an interview's findings were built. LEADERSHIP: a leadership
  # context was built. CONSULTANT: a review decision changed effort or scope.
  TRIGGERS = %w[FINDINGS LEADERSHIP CONSULTANT MANUAL REPORT].freeze
  # PARTIAL: consolidation ran but P11 could not be used, so findings and
  # clusters pass forward unsynthesised (P11 §9).
  STATUSES = %w[QUEUED RUNNING COMPLETE PARTIAL FAILED].freeze
  FINISHED = %w[COMPLETE PARTIAL].freeze
  PICTURE_STATUSES = %w[PROPOSED APPROVED REJECTED].freeze

  belongs_to :company
  belongs_to :engagement
  has_many :process_relationships, dependent: :nullify
  has_many :synthesis_clusters, dependent: :nullify
  has_many :consultancy_opportunities, dependent: :nullify
  has_many :root_causes, dependent: :nullify
  has_many :management_validations, dependent: :nullify

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }
  validates :operating_picture_status, inclusion: { in: PICTURE_STATUSES }
  validates :version, presence: true, uniqueness: { scope: :engagement_id }

  scope :finished, -> { where(status: FINISHED) }

  def self.latest_finished(engagement) = where(engagement: engagement).finished.order(version: :desc).first

  def finished? = FINISHED.include?(status)

  # What the report would print: the consultant's picture where they edited it.
  def display_operating_picture
    consultant_operating_picture.presence || operating_picture
  end
end
