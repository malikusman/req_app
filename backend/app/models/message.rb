# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :employee_submission, optional: true
  belongs_to :reply_to_message, class_name: "Message", optional: true
  has_many :discovery_replies, class_name: "Message", foreign_key: :reply_to_message_id, dependent: :destroy
  belongs_to :conversation
  belongs_to :track_ref, polymorphic: true, optional: true
  has_one :media_attachment, dependent: :destroy
  has_one :document, dependent: :nullify
  has_one :discovery_question_feedback, dependent: :destroy

  DIRECTIONS = %w[inbound outbound].freeze
  TYPES = %w[text audio image document interactive system].freeze
  PROCESSING_STATUSES = %w[pending processing ready failed].freeze

  # Which conversation the turn belongs to. One employee keeps one thread across
  # all of these, so the track is what tells an answer to a consultant's question
  # apart from a companion aside.
  TRACKS = %w[onboarding profiling discovery companion consultant_followup system].freeze

  # Tracks the employee sees in their own thread. `system` is internal plumbing.
  EMPLOYEE_VISIBLE_TRACKS = %w[onboarding profiling discovery companion consultant_followup].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :message_type, inclusion: { in: TYPES }
  validates :processing_status, inclusion: { in: PROCESSING_STATUSES }
  validates :track, inclusion: { in: TRACKS }

  after_commit :advance_discovery_snapshot, on: [:create, :update], if: -> { saved_change_to_body? || saved_change_to_processing_status? || saved_change_to_raw_payload? }
  def advance_discovery_snapshot
    Conversation.where(id: conversation_id).update_all('discovery_state_version = discovery_state_version + 1')
  end
  after_commit :enqueue_discovery_delivery, if: -> { delivery_status == 'pending' }
  def enqueue_discovery_delivery
    DeliverDiscoveryReplyJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[DiscoveryDelivery] enqueue failed message=#{id} error=#{e.class}; sweep will recover")
  end
  before_validation :attach_submission, on: :create
  def attach_submission
    self.employee_submission = DiscoveryRequest.submission if direction == 'inbound' && message_type != 'system' && DiscoveryRequest.submission
  end
  before_validation :derive_track, on: :create
  before_validation :sync_consultant_followup_flag

  # Retained for the platform/company transcript views and their index. Reads the
  # legacy boolean deliberately — `track` is the source of truth, and
  # `sync_consultant_followup_flag` keeps the boolean in step.
  scope :discovery_only, -> { where(consultant_followup: false) }
  scope :consultant_followup_only, -> { where(consultant_followup: true) }

  scope :on_track, ->(*tracks) { where(track: tracks.flatten) }
  scope :employee_visible, -> { where(track: EMPLOYEE_VISIBLE_TRACKS) }

  def consultant_followup?
    track == "consultant_followup"
  end

  def companion?
    track == "companion"
  end

  private

  # Explicit `track:` at the creation site always wins. This is the safety net for
  # sites that don't pass one — it infers from what the rest of the row says rather
  # than letting a message land with no track at all.
  def derive_track
    return if track.present?

    self.track =
      if message_type == "system" then "system"
      elsif consultant_followup then "consultant_followup"
      elsif agent_id == "companion" || routing_decision.to_h["action"].to_s.start_with?("companion")
        "companion"
      elsif conversation&.status.in?(%w[onboarding profiling])
        conversation.status
      else
        "discovery"
      end
  end

  # Keep the legacy boolean consistent with the track so the older scopes and the
  # partial index stay correct while both exist.
  def sync_consultant_followup_flag
    self.consultant_followup = (track == "consultant_followup") unless track.nil?
  end
end
