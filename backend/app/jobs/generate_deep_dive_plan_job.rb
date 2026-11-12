# frozen_string_literal: true

class GenerateDeepDivePlanJob < ApplicationJob
  queue_as :default

  def perform(plan_id, token, consultant_id)
    plan = DeepDivePlan.find_by(id: plan_id)
    return unless plan

    plan.with_lock do
      return unless plan.status == "queued" && plan.generation_token == token

      plan.update!(status: "generating")
    end
    actor = ConsultantUser.active.find_by(id: consultant_id)
    company_id = plan.task_selection_revision.task_selection_review.company_id
    unless actor&.active_company_ids&.include?(company_id)
      self.class.fail_attempt(plan, token, "The requesting consultant no longer has access.")
      return
    end

    context = plan.context.merge("participants" => plan.context.fetch("participants").map { |person| person.except("display_name") })
    result = Langgraph::Client.new.generate_deep_dive_plan!(context: context)
    raise DeepDivePlans::Invalid unless result["generated_by"] == "llm"

    content = DeepDivePlans::Content.new(plan.context).validate(result["plan"], generated: true)
    plan.with_lock do
      return unless plan.status == "generating" && plan.generation_token == token

      plan.revisions.create!(version: 1, consultant_user: actor, action: "generated", reason: "Requested AI interview plan.", content: content)
      plan.update!(status: "draft")
    end
  rescue Langgraph::UnavailableError
    self.class.fail_attempt(plan, token, "AI generation is unavailable or failed. Check the configured model and try again.")
  rescue DeepDivePlans::Invalid
    self.class.fail_attempt(plan, token, "AI returned an incomplete or invalid plan. Try again.")
  rescue StandardError => e
    Rails.logger.error("[GenerateDeepDivePlanJob] plan=#{plan_id} error=#{e.class}")
    self.class.fail_attempt(plan, token, "Plan generation failed. Try again.") if plan
  end

  def self.fail_attempt(plan, token, message)
    plan.with_lock do
      if plan.status.in?(%w[queued generating]) && plan.generation_token == token
        plan.update!(status: "failed", generation_error: message)
      end
    end
  end
end
