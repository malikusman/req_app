# frozen_string_literal: true

class DeliverOutreachJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound do |job, error|
    Rails.logger.warn("[DeliverOutreachJob] discarding job #{job.job_id}: #{error.message}")
  end

  def perform(outreach_id)
    outreach = ConsultantOutreach.find(outreach_id)
    Outreaches::DeliverService.call(outreach: outreach)
  end
end
