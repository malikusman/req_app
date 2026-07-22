# frozen_string_literal: true

module Registrations
  class RejectReviewerApplication
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
        status: "rejected",
        rejected_at: Time.current
      )
      SignupMailer.reviewer_application_rejected(@reviewer).deliver_later
      @reviewer
    end
  end
end
