# frozen_string_literal: true

module Reports
  # Share links are per-variant: "send the board the brief" and "share
  # everything" are different acts, and the copied link says which it opens.
  #
  # reports.share_token is still written for the full variant so links already
  # in a client's inbox keep resolving. New links always get a ReportShare row.
  class ShareLinkService
    def self.create!(report:, days: 30, variant: VariantSpec::FULL)
      new(report: report, days: days, variant: variant).create!
    end

    # Kill share links immediately — the public URLs stop resolving. Pass a
    # variant to revoke just that one.
    def self.revoke!(report:, variant: nil)
      scope = report.report_shares.live
      scope = scope.where(variant: variant.to_s) if variant.present?
      scope.each(&:revoke!)

      # The legacy column backs the full variant, so only clear it when the full
      # variant (or everything) is being revoked.
      if variant.blank? || variant.to_s == VariantSpec::FULL
        report.update!(share_token: nil, share_token_expires_at: nil)
      end
      report
    end

    def initialize(report:, days: 30, variant: VariantSpec::FULL)
      @report = report
      @days = days.to_i.positive? ? days.to_i : 30
      @spec = VariantSpec.for(variant)
    end

    def create!
      raise ArgumentError, "Report not ready" unless @report.status == "ready"
      raise ArgumentError, "Report not shareable" unless @report.visibility == "shared_with_company"
      raise ArgumentError, "#{@spec[:label]} has not been rendered for this report" unless rendered?

      token = SecureRandom.urlsafe_base64(32)
      expires = @days.days.from_now

      # Replacing a link revokes the old one rather than leaving two live URLs
      # for the same rendering, which is what "reshare" should mean.
      @report.report_shares.live.where(variant: @spec[:variant]).each(&:revoke!)
      share = @report.report_shares.create!(
        variant: @spec[:variant], token: token, expires_at: expires
      )

      if @spec[:variant] == VariantSpec::FULL
        @report.update!(share_token: token, share_token_expires_at: expires)
      end

      NotificationService.notify_report_shared(company: @report.company, report: @report)

      {
        share_token: token,
        variant: @spec[:variant],
        variant_label: @spec[:label],
        share_url: public_url(token),
        expires_at: expires,
        id: share.id
      }
    end

    private

    def rendered?
      if @spec[:variant] == VariantSpec::FULL
        @report.storage_key.present?
      else
        @report.artifact_for(@spec[:variant])&.storage_key.present?
      end
    end

    def public_url(token)
      api_host = ENV.fetch("API_PUBLIC_HOST", ENV.fetch("APP_HOST", "http://localhost:3000"))
      "#{api_host}/api/v1/public/reports/#{token}"
    end
  end
end
