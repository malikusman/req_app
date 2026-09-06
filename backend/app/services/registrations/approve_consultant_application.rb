# frozen_string_literal: true

module Registrations
  class ApproveConsultantApplication
    class Error < StandardError; end

    def self.call(consultant:, platform_user:, review_note: nil)
      new(consultant: consultant, platform_user: platform_user, review_note: review_note).call
    end

    def initialize(consultant:, platform_user:, review_note: nil)
      @consultant = consultant
      @platform_user = platform_user
      @review_note = review_note
    end

    def call
      raise Error, "Application is not pending" unless @consultant.status == "pending"

      @consultant.update!(
        status: "active",
        approved_at: Time.current,
        rejected_at: nil
      )

      token = Auth::PasswordResetToken.generate(@consultant)
      SignupMailer.consultant_application_approved(@consultant, token).deliver_later
      @consultant
    end
  end
end
