# frozen_string_literal: true

# Stage 1 pricing's messages (Doc 21 §42). To administrators: a quote awaiting
# approval — flagged when it is below the margin floor — and pricing that can't
# go ahead. To the client's key user: their proposal is ready, with the total
# and a link, and nothing internal (Doc 17 §15). To Mjadi: the client's
# decision.
class PricingMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def quote_awaiting_approval(quote)
    setup(quote)
    @url = "#{NotificationService.app_host}/platform/pricing/#{quote.id}"
    prefix = quote.below_floor ? "Below margin floor — " : ""
    mail(to: approvers, subject: "#{prefix}Stage 1 quote for #{@company_name} awaiting approval")
  end

  def pricing_blocked(engagement, reason)
    @engagement = engagement
    @company_name = company_name(engagement.company)
    @reason = reason
    @url = "#{NotificationService.app_host}/platform/companies/#{engagement.company_id}"
    mail(to: approvers, subject: "Stage 1 pricing for #{@company_name} can't go ahead")
  end

  # The client accepted or declined, or the quote expired unanswered.
  def client_outcome(quote)
    setup(quote)
    @outcome = Pricing::Notifications::OUTCOMES.fetch(quote.status)
    @url = "#{NotificationService.app_host}/platform/pricing/#{quote.id}"
    mail(to: approvers, subject: "Stage 1 proposal for #{@company_name} #{@outcome}")
  end

  private

  def setup(quote)
    @quote = quote
    @company_name = company_name(quote.company)
    @total = Pricing::Money.format(quote.total, quote.currency)
  end

  def company_name(company) = company.display_name.presence || company.name

  # Only super admins act on prices.
  def approvers = PlatformUser.where(role: PricingPolicy::APPROVER_ROLE).pluck(:email)
end
