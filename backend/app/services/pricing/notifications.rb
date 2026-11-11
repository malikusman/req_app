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

    # Issued: the key user is told in the portal and by email (the
    # notification's own email), with the total and a link — nothing more.
    def self.issued(quote)
      key_user = quote.engagement.key_user
      return unless key_user

      NotificationService.notify(
        type: :stage1_quote_ready, company: quote.company, recipients: [key_user],
        title: "Your Stage 1 proposal is ready",
        body: "Your Stage 1 proposal from Mjadi is ready: #{Money.format(quote.total, quote.currency)} including tax, "               "for #{quote.participants_included} people and #{quote.deep_dives_included} detailed sessions. "               "It stands until #{quote.valid_until.strftime('%-d %B %Y')}.",
        action_url: "#{NotificationService.app_host}/company/proposal",
        metadata: { quote_id: quote.id }
      )
    end

    # Accepted, declined or expired: the super admins by email, the lead
    # consultant in the portal.
    def self.decided(quote)
      PricingMailer.client_outcome(quote).deliver_later
      consultant = quote.engagement.lead_consultant
      return unless consultant

      NotificationService.notify(
        type: :stage1_quote_decided, company: quote.company, recipients: [consultant],
        title: "Stage 1 proposal #{OUTCOMES.fetch(quote.status)}",
        body: "#{company_name(quote)}'s Stage 1 proposal was #{OUTCOMES.fetch(quote.status)}."               "#{quote.decline_reason.present? ? " Their reason: #{quote.decline_reason}" : ''}",
        action_url: "#{NotificationService.app_host}/consultant/companies/#{quote.company_id}",
        metadata: { quote_id: quote.id, engagement_id: quote.engagement_id }
      )
    end

    OUTCOMES = { "ACCEPTED" => "accepted", "DECLINED" => "declined", "EXPIRED" => "not accepted in time" }.freeze

    def self.company_name(quote) = quote.company.display_name.presence || quote.company.name
  end
end
