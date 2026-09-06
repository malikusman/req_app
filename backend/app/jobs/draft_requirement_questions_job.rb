# frozen_string_literal: true

# Drafts questions for a consultant's stated need.
#
# Off the request path deliberately: drafting is an LLM call that can take well over
# a minute, and a consultant should not watch a spinner for it. The requirement is
# saved immediately; its questions appear when this finishes.
class DraftRequirementQuestionsJob < ApplicationJob
  queue_as :default

  def perform(requirement_id)
    requirement = ConsultantRequirement.find_by(id: requirement_id)
    return unless requirement
    return unless requirement.open?

    ConsultantRequirements::DraftQuestionsService.call(requirement: requirement)
  rescue StandardError => e
    # The stated need survives a failed draft, and the consultant can retry.
    Rails.logger.error("[DraftRequirementQuestionsJob] requirement=#{requirement_id} #{e.class}: #{e.message}")
  end
end
