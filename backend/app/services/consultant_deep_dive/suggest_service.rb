# frozen_string_literal: true

module ConsultantDeepDive
  # What else is worth asking this employee, proposed to the consultant with a
  # reason, before they decide anything.
  #
  # The requirement loop starts from a need the consultant already has. This starts
  # one turn earlier: discovery stays deliberately light, so by review time there
  # are things worth knowing that nobody has thought to ask yet. The agent can see
  # which, because it can see what the dossier captured and what it did not.
  #
  # Read-only and side-effect free ON PURPOSE. Nothing is persisted, nothing is
  # sent, no budget is spent. A suggestion costs the employee nothing until the
  # consultant accepts it, at which point it becomes an ordinary
  # ConsultantRequirement and is capped by the existing per-package budget the same
  # as any other question. That is what makes it safe to suggest generously.
  class SuggestService
    def self.call(package:, max_suggestions: nil)
      new(package: package, max_suggestions: max_suggestions).call
    end

    def initialize(package:, max_suggestions: nil)
      @package = package
      @company = package.company
      @employee = package.employee
      @max_suggestions = max_suggestions
    end

    def call
      budget = Discovery::FollowupLimits.package_budget_remaining(@package)
      # Never propose more than the employee could actually be asked. A list of five
      # good questions when two can be sent is a triage job handed to the
      # consultant, not help given to them.
      allowance = [@max_suggestions || DEFAULT_SUGGESTIONS, budget].compact.min

      return empty(budget, reason: "no_budget") unless allowance.positive?

      payload = fetch(allowance)
      suggestions = Array(payload["suggestions"]).filter_map { |s| normalize(s) }

      if payload["generated_by"] == "deterministic"
        Rails.logger.info(
          "[ConsultantDeepDive::Suggest] package=#{@package.id} deterministic " \
          "suggestions: #{payload['fallback_reason']}"
        )
      end

      {
        suggestions: suggestions,
        budget_remaining: budget,
        generated_by: payload["generated_by"],
        fallback_reason: payload["fallback_reason"]
      }
    rescue Langgraph::UnavailableError => e
      # A review that opens without suggestions is a degraded surface; a review that
      # 500s is a broken one. The consultant can still state their own need.
      Rails.logger.warn("[ConsultantDeepDive::Suggest] package=#{@package.id} #{e.message}")
      empty(Discovery::FollowupLimits.package_budget_remaining(@package), reason: "agent_unavailable")
    end

    DEFAULT_SUGGESTIONS = 3

    private

    def empty(budget, reason:)
      { suggestions: [], budget_remaining: budget, generated_by: "none", fallback_reason: reason }
    end

    def fetch(allowance)
      Langgraph::Client.new.suggest_deep_dive_questions!(
        package: package_context,
        dossier: dossier,
        profile: @package.conversation.blackboard["profile"] || @employee.profile_card,
        already_asked: already_asked,
        max_suggestions: allowance,
        language: @employee.preferred_language.presence || @company.locale || "en"
      )
    end

    # What the interview concluded — the same shape the requirement drafter gets, so
    # both agents reason about the package the same way.
    def package_context
      {
        "recommendation" => @package.recommendation,
        "issues" => @package.issues.map { |i| { "title" => i.title, "body" => i.body } },
        "solutions" => @package.solutions.map { |s| { "title" => s.title, "body" => s.body } }
      }
    end

    # The dossier is what lets the agent spot a gap rather than guess at one: a
    # friction with no friction_cost beside it is the difference between a described
    # problem and a measured one, and that is visible here without any judgement.
    def dossier
      @package.conversation.blackboard["dossier"] || {}
    end

    # Everything already put to this employee for this package, so a suggestion
    # never repeats a question they have already answered.
    def already_asked
      @package.discovery_followup_questions.where.not(status: "superseded").pluck(:body)
    end

    def normalize(raw)
      return nil unless raw.is_a?(Hash)

      body = raw["body"].to_s.strip
      rationale = raw["rationale"].to_s.strip
      return nil if body.blank? || rationale.blank?

      { body: body, rationale: rationale, kind: raw["kind"].presence || "mechanism" }
    end
  end
end
