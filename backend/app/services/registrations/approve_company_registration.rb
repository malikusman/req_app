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
        # Approving a request opens the engagement; there is no trial to run out.
        company.engagements.create!(
          key_user: @registration.company_user,
          languages: [company.locale.presence || "en"],
          status_history: [{ "from" => nil, "to" => "SET_UP", "at" => Time.current.iso8601,
                             "by_type" => @platform_user.class.name, "by_id" => @platform_user.id }]
        ) unless company.current_engagement

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
