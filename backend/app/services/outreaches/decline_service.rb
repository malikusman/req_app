# frozen_string_literal: true

module Outreaches
  class DeclineService
    def self.call(outreach:, admin:, note: nil)
      new(outreach: outreach, admin: admin, note: note).call
    end

    def initialize(outreach:, admin:, note: nil)
      @outreach = outreach
      @admin = admin
      @note = note
    end

    def call
      raise ArgumentError, "Outreach is not pending approval" unless @outreach.pending_admin?

      @outreach.update!(
        status: "declined",
        declined_at: Time.current,
        approved_by_company_user: @admin,
        admin_note: @note
      )
      @outreach.append_audit!("declined", actor: @admin, note: @note)
      @outreach
    end
  end
end
