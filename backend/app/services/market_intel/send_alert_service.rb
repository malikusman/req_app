# frozen_string_literal: true

module MarketIntel
  class SendAlertService
    def self.call(alert:)
      new(alert: alert).call
    end

    def initialize(alert:)
      @alert = alert
    end

    def call
      employee = @alert.employee
      preference = employee.employee_value_preference
      raise ArgumentError, "Employee is not opted in" unless preference&.subscribed?
      raise ArgumentError, "Employee has no email" if employee.email.blank?
      raise ArgumentError, "Stub candidates cannot be emailed" if @alert.catalog_candidate.stub?

      month = EmployeeMarketAlert.period_month_for
      if EmployeeMarketAlert.sent_count_this_month(employee.id) >= max_per_month
        @alert.update!(status: "suppressed", delivery_status: "monthly_cap", period_month: month)
        return @alert
      end

      MarketAlertsMailer.alert_email(@alert).deliver_later
      @alert.update!(
        status: "sent",
        delivery_status: "queued",
        sent_at: Time.current,
        period_month: month
      )
      @alert
    rescue StandardError => e
      @alert.update!(status: "failed", delivery_status: e.message.to_s.truncate(200))
      raise
    end

    private

    def max_per_month
      ENV.fetch("AI_MARKET_ALERT_MAX_PER_MONTH", "2").to_i.clamp(1, 8)
    end
  end
end
