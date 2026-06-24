# frozen_string_literal: true

module Employees
  class NudgeService
    class NudgeError < StandardError; end

    class CooldownError < NudgeError
      attr_reader :retry_after_hours

      def initialize(retry_after_hours)
        @retry_after_hours = retry_after_hours
        super("Nudge cooldown active")
      end
    end

    Result = Struct.new(:nudge, :message, keyword_init: true)

    def self.call(employee:, company_user:)
      new(employee: employee, company_user: company_user).call
    end

    def initialize(employee:, company_user:)
      @employee = employee
      @company_user = company_user
    end

    def call
      validate!

      nudge = EmployeeNudge.create!(
        employee: @employee,
        company_user: @company_user,
        conversation: @employee.conversations.order(updated_at: :desc).first,
        channel: channel_for_nudge,
        delivery_status: "queued",
        whatsapp_status: "queued",
        email_status: email_channel? ? "queued" : "skipped",
        sent_at: Time.current
      )

      SendEmployeeNudgeJob.perform_later(nudge.id)

      Result.new(nudge: nudge, message: "Nudge queued")
    end

    private

    def validate!
      raise NudgeError, "Employee already completed" if @employee.participation_status == "completed"
      raise NudgeError, "Employee has not started discovery" unless @employee.participation_status == "started"
      raise NudgeError, "Employee phone number is missing" if @employee.phone_e164.blank?

      if cooldown_active?
        raise CooldownError.new(cooldown_hours_remaining)
      end
    end

    def cooldown_active?
      return true if @employee.last_nudged_at.present? &&
                     @employee.last_nudged_at > SendEmployeeNudgeJob::NUDGE_COOLDOWN.ago

      @employee.employee_nudges
               .where(delivery_status: %w[queued sent partial])
               .where("sent_at > ?", SendEmployeeNudgeJob::NUDGE_COOLDOWN.ago)
               .exists?
    end

    def cooldown_hours_remaining
      anchor = [
        @employee.last_nudged_at,
        @employee.employee_nudges.maximum(:sent_at)
      ].compact.max
      return 0 unless anchor

      ((anchor + SendEmployeeNudgeJob::NUDGE_COOLDOWN) - Time.current) / 1.hour
    end

    def email_channel?
      @employee.email.present?
    end

    def channel_for_nudge
      email_channel? ? "whatsapp_and_email" : "whatsapp_template"
    end
  end
end
