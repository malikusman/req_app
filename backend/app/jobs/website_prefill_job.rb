# frozen_string_literal: true

# Reads the client's website for onboarding pre-fill (Doc 07 §5). A site that
# can't be reached is tried once more ten minutes later; after that the client
# simply gets the plain form (§5.5).
class WebsitePrefillJob < ApplicationJob
  queue_as :default

  retry_on Companies::WebsiteFetcher::Unreachable, wait: 10.minutes, attempts: 2 do |job, error|
    engagement = Engagement.find_by(id: job.arguments.first)
    engagement&.update!(prefill_status: "failed", prefill_error: "unreachable: #{error.message}".truncate(200),
                        prefill_finished_at: Time.current)
  end

  def perform(engagement_id)
    engagement = Engagement.find_by(id: engagement_id)
    return unless engagement

    Companies::WebsitePrefill.call(engagement: engagement)
  end

  # Marks the engagement pending, so the form knows to wait for the proposals,
  # and queues the read.
  def self.start(engagement)
    return if engagement.company.website_url.blank?

    engagement.update!(prefill_status: "pending", prefill_error: nil)
    perform_later(engagement.id)
  end
end
