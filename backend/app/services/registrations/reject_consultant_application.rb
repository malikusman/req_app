# frozen_string_literal: true

module Registrations
  class RejectConsultantApplication
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
        status: "rejected",
        rejected_at: Time.current
      )
      SignupMailer.consultant_application_rejected(@consultant).deliver_later
      @consultant
    end
  end
end
