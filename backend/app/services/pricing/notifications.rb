# frozen_string_literal: true

module Pricing
  # Who hears what about a Stage 1 quote (Doc 21 §42). Administrators are
  # emailed by PricingMailer; consultants and the client get portal
  # notifications. Nothing internal is in any of them (Doc 17 §15).
  module Notifications
    # Sent back by an administrator: the lead consultant follows it up with the
    # client, say when the plan looks wrong.
    def self.rejected(quote)
      consultant = quote.engagement.lead_consultant
      return unless consultant

      NotificationService.notify(
        type: :stage1_quote_rejected, company: quote.company, recipients: [consultant],
        title: "Stage 1 quote sent back",
        body: "The Stage 1 quote for #{company_name(quote)} was sent back: #{quote.rejection_note}",
        action_url: "#{NotificationService.app_host}/consultant/companies/#{quote.company_id}",
        metadata: { quote_id: quote.id, engagement_id: quote.engagement_id }
      )
    end

    def self.company_name(quote) = quote.company.display_name.presence || quote.company.name
  end
end
