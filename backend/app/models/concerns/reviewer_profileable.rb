# frozen_string_literal: true

module ReviewerProfileable
  extend ActiveSupport::Concern

  PROFILE_STATUSES = %w[draft published].freeze

  included do
    has_many :reviewer_experiences, dependent: :destroy

    validates :profile_status, inclusion: { in: PROFILE_STATUSES }
    validates :linkedin_url, format: { with: %r{\Ahttps?://}i, allow_blank: true }
    validates :website_url, format: { with: %r{\Ahttps?://}i, allow_blank: true }
    validates :years_experience, allow_nil: true, numericality: { greater_than_or_equal_to: 0, less_than: 80 }
    validate :expertise_tags_limit

    before_save :sync_profile_completed_timestamp
  end

  def published_profile?
    profile_status == "published"
  end

  private

  def expertise_tags_limit
    return if expertise_tags.blank? || expertise_tags.size <= 12

    errors.add(:expertise_tags, "cannot exceed 12 tags")
  end

  def sync_profile_completed_timestamp
    result = Reviewers::ProfileCompleteness.call(self)
    self.profile_completed_at = result.complete ? (profile_completed_at || Time.current) : nil
  end
end
