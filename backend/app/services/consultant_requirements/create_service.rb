# frozen_string_literal: true

module ConsultantRequirements
  # Records what a consultant needs to know and drafts questions from it.
  #
  # The consultant never writes question text. This is the whole reason the
  # requirement exists as its own object: their statement is the input, and the
  # questions are generated artifacts that can be redrafted, reordered or skipped
  # without losing what they actually asked for.
  class CreateService
    def self.call(package:, consultant:, statement:)
      new(package: package, consultant: consultant, statement: statement).call
    end

    def initialize(package:, consultant:, statement:)
      @package = package
      @consultant = consultant
      @statement = statement.to_s.strip
      @company = package.company
    end

    def call
      raise ArgumentError, "Statement required" if @statement.blank?

      requirement = ConsultantRequirement.create!(
        consultant_user: @consultant,
        discovery_package: @package,
        employee: @package.employee,
        company: @company,
        statement: @statement,
        max_questions: Discovery::FollowupLimits.max_per_requirement(@company),
        status: "open"
      )

      # Enqueued, not inline: drafting is an LLM call and the consultant should get
      # their requirement back immediately rather than waiting on the model.
      DraftRequirementQuestionsJob.perform_later(requirement.id)
      requirement
    end
  end
end
