# frozen_string_literal: true

# Drafts the cause and direction of findings off the request path: after an
# interview's findings are built, and after a consultant rewords one. Swallows
# failures — an undrafted finding is redrafted when the next report is generated.
class DraftFindingCausesJob < ApplicationJob
  queue_as :default

  def perform(finding_ids)
    findings = Finding.where(id: finding_ids).live.includes(:company).to_a
    Findings::DraftCauseAndDirection.call(findings: findings)
  rescue StandardError => e
    Rails.logger.error("[DraftFindingCausesJob] findings=#{Array(finding_ids).first(10)} #{e.class}: #{e.message}")
  end
end
