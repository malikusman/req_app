# frozen_string_literal: true

class DocumentAnalysisRunJob < ApplicationJob
  queue_as :default
  # Large batches may take several minutes
  sidekiq_options retry: 1

  def perform(run_id)
    Documents::AnalysisRunService.call(run_id: run_id)
  end
end
