# frozen_string_literal: true

module Reports
  class ShareLinkService
    def self.create!(report:, days: 30)
      new(report: report, days: days).create!
    end

    def initialize(report:, days: 30)
      @report = report
      @days = days.to_i.positive? ? days.to_i : 30
    end

    def create!
      raise ArgumentError, "Report not ready" unless @report.status == "ready"
      raise ArgumentError, "Report not shareable" unless @report.visibility == "shared_with_company"

      token = SecureRandom.urlsafe_base64(32)
      expires = @days.days.from_now

      @report.update!(share_token: token, share_token_expires_at: expires)

      NotificationService.notify_report_shared(company: @report.company, report: @report)

      {
        share_token: token,
        share_url: public_url(token),
        expires_at: expires
      }
    end

    private

    def public_url(token)
      api_host = ENV.fetch("API_PUBLIC_HOST", ENV.fetch("APP_HOST", "http://localhost:3000"))
      "#{api_host}/api/v1/public/reports/#{token}"
    end
  end
end
