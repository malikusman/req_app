# frozen_string_literal: true

module ConsultantDeepDive
  # The consultant accepted a suggested question. Turn it into a real requirement.
  #
  # It becomes an ordinary ConsultantRequirement so that everything downstream is
  # unchanged: the same send path, the same attribution of the employee's reply, the
  # same satisfaction judgement, the same budgets. A suggestion is only a different
  # way of ARRIVING at a need, not a different kind of need.
  #
  # The suggested question text is persisted directly rather than re-drafted. The
  # consultant approved those words; sending the requirement through the drafting
  # job would generate different ones and quietly discard their decision — and pay
  # for a second model call to do it.
  #
  # The rationale becomes the requirement's statement, because that IS the need:
  # "they described this but never put a time to it" is exactly what a consultant
  # would have written by hand, and it is what the satisfaction judge later reads to
  # decide whether the answer settled anything.
  class AcceptService
    class BudgetExhausted < StandardError; end

    def self.call(package:, consultant:, body:, rationale:)
      new(package: package, consultant: consultant, body: body, rationale: rationale).call
    end

    def initialize(package:, consultant:, body:, rationale:)
      @package = package
      @consultant = consultant
      @body = body.to_s.strip
      @rationale = rationale.to_s.strip
      @company = package.company
    end

    def call
      raise ArgumentError, "Question text required" if @body.blank?

      if Discovery::FollowupLimits.package_budget_remaining(@package).zero?
        raise BudgetExhausted, "This employee has already been asked the maximum for this package."
      end

      requirement = nil
      question = nil

      ActiveRecord::Base.transaction do
        requirement = ConsultantRequirement.create!(
          consultant_user: @consultant,
          discovery_package: @package,
          employee: @package.employee,
          company: @company,
          statement: @rationale.presence || @body,
          max_questions: Discovery::FollowupLimits.max_per_requirement(@company),
          # Already drafted — there is nothing for the drafting job to do.
          status: "questions_drafted"
        )

        question = @package.discovery_followup_questions.create!(
          consultant_requirement: requirement,
          body: @body,
          rationale: @rationale.presence,
          status: "drafted",
          queue_position: (@package.discovery_followup_questions.maximum(:queue_position) || 0) + 1
        )
      end

      { requirement: requirement, question: question }
    end
  end
end
