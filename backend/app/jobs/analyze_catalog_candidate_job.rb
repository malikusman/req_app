# frozen_string_literal: true

class AnalyzeCatalogCandidateJob < ApplicationJob
  queue_as :default

  def perform(candidate_id)
    candidate = CatalogCandidate.find_by(id: candidate_id)
    return unless candidate

    Catalog::AnalyzeCandidateService.call(candidate: candidate)
  end
end
