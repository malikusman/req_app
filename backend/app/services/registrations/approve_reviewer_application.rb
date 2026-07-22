# frozen_string_literal: true

module Registrations
  class ApproveReviewerApplication
    class Error < StandardError; end

    def self.call(reviewer:, platform_user:, review_note: nil)
      new(reviewer: reviewer, platform_user: platform_user, review_note: review_note).call
    end

    def initialize(reviewer:, platform_user:, review_note: nil)
      @reviewer = reviewer
      @platform_user = platform_user
      @review_note = review_note
    end

    def call
      raise Error, "Application is not pending" unless @reviewer.status == "pending"

      @reviewer.update!(
        status: "active",
        approved_at: Time.current,
        rejected_at: nil
      )

      token = Auth::PasswordResetToken.generate(@reviewer)
      SignupMailer.reviewer_application_approved(@reviewer, token).deliver_later
      @reviewer
    end
  end
end
