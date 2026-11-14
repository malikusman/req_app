# frozen_string_literal: true

module Registrations
  # Approving a sign-up request is Mjadi setting up the engagement (Doc 07 §3):
  # the admin supplies what the request lacked — scope, departments, lead
  # consultant, languages, proposal — and the requester becomes the key user and
  # is invited. No account works before this.
  class ApproveCompanyRegistration
    class Error < StandardError; end

    def self.call(registration:, platform_user:, review_note: nil, engagement_params: {}, request: nil)
      new(registration: registration, platform_user: platform_user, review_note: review_note,
          engagement_params: engagement_params, request: request).call
    end

    def initialize(registration:, platform_user:, review_note: nil, engagement_params: {}, request: nil)
      @registration = registration
      @platform_user = platform_user
      @review_note = review_note.to_s.strip.presence
      @engagement_params = engagement_params.to_h.deep_stringify_keys
      @request = request
    end

    def call
      raise Error, "Registration already reviewed" unless @registration.pending?

      ActiveRecord::Base.transaction do
        @registration.update!(
          status: "approved",
          reviewed_by_platform_user: @platform_user,
          reviewed_at: Time.current,
          review_note: @review_note
        )
        # Last, so nothing after it can roll back an invitation already sent.
        Engagements::Create.call(platform_user: @platform_user, params: engagement_params,
                                 company: @registration.company, key_user: @registration.company_user,
                                 request: @request)
      end
      @registration.reload
    rescue Engagements::Create::Error => e
      raise Error, e.message
    end

    private

    # What the requester told us fills in the key user's role and the website;
    # the admin's entries win where both exist.
    def engagement_params
      defaults = { "key_user" => { "role_title" => @registration.role_title } }
      defaults.deep_merge(@engagement_params) { |_key, ours, theirs| theirs.presence || ours }
    end
  end
end
