# frozen_string_literal: true

module Registrations
  class ApproveCompanyRegistration
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
        company = @registration.company
        company.update!(
          approval_status: "approved",
          approved_at: Time.current,
          rejected_at: nil
        )
        Subscription.find_or_create_by!(company: company) do |sub|
          sub.plan = "trial"
          sub.status = "trial"
          sub.trial_ends_at = 14.days.from_now
        end

        @registration.update!(
          status: "approved",
          reviewed_by_platform_user: @platform_user,
          reviewed_at: Time.current,
          review_note: @review_note
        )
      end

      token = Auth::PasswordResetToken.generate(@registration.company_user)
      SignupMailer.company_registration_approved(@registration, token).deliver_later
      @registration.reload
    end
  end
end
