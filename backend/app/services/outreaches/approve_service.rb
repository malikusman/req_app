# frozen_string_literal: true

module Outreaches
  class ApproveService
    def self.call(outreach:, admin:, edited_body: nil, note: nil, employee_id: nil)
      new(outreach: outreach, admin: admin, edited_body: edited_body, note: note, employee_id: employee_id).call
    end

    def initialize(outreach:, admin:, edited_body: nil, note: nil, employee_id: nil)
      @outreach = outreach
      @admin = admin
      @edited_body = edited_body
      @note = note
      @employee_id = employee_id
    end

    def call
      raise ArgumentError, "Outreach is not pending approval" unless @outreach.pending_admin?

      attrs = {
        status: "approved",
        approved_by_company_user: @admin,
        approved_at: Time.current,
        admin_note: @note
      }
      attrs[:edited_body] = @edited_body if @edited_body.present?

      if @employee_id.present? && @employee_id.to_i != @outreach.employee_id
        employee = @outreach.company.employees.find(@employee_id)
        attrs[:employee] = employee
        attrs[:recipient_id] = employee.id
        attrs[:conversation] = employee.conversations.order(updated_at: :desc).first
      end

      @outreach.update!(attrs)
      @outreach.append_audit!("approved", actor: @admin, note: @note)
      DeliverOutreachJob.perform_later(@outreach.id)
      @outreach
    end
  end
end
