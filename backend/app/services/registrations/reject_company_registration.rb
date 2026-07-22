# frozen_string_literal: true

module Registrations
  class RejectCompanyRegistration
    class Error < StandardError; end

    def self.call(registration:, platform_user:, review_note: nil)
      new(registration: registration, platform_user: platform_user, review_note: review_note).call
    end

    def initialize(registration:, platform_user:, review_note: nil)
      @registration = registration
      @platform_user = platform_user
      @review_note = review_note.to_s.strip.presence
    end

    def call
      raise Error, "Registration already reviewed" unless @registration.pending?

      ActiveRecord::Base.transaction do
        @registration.company.update!(
          approval_status: "rejected",
          rejected_at: Time.current
        )
        @registration.company_user.update!(status: "deactivated")
        @registration.update!(
          status: "rejected",
          reviewed_by_platform_user: @platform_user,
          reviewed_at: Time.current,
          review_note: @review_note
        )
      end

      SignupMailer.company_registration_rejected(@registration).deliver_later
      @registration.reload
    end
  end
end
