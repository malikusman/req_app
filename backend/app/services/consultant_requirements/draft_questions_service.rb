# frozen_string_literal: true

module ConsultantRequirements
  # Asks the agent for the next question(s) for a stated need.
  #
  # Bounded twice over: by the requirement's own budget, and by what the employee
  # has already been asked for this package. The second one is the important cap —
  # three requirements each spending three questions is nine questions to one
  # person, more than the entire discovery interview is allowed.
  class DraftQuestionsService
    def self.call(requirement:)
      new(requirement: requirement).call
    end

    def initialize(requirement:)
      @requirement = requirement
      @package = requirement.discovery_package
      @company = requirement.company
    end

    def call
      allowance = [@requirement.budget_remaining, package_remaining].min
      return [] unless allowance.positive?

      payload = fetch_draft(allowance)
      # The agent never raises for drafting — it falls back to a canned template and
      # says why in fallback_reason. Rails discarded that, so a consultant silently
      # received a stiff templated question with nothing anywhere explaining that the
      # model call had failed. Surface it.
      if payload["generated_by"] == "deterministic"
        Rails.logger.warn(
          "[ConsultantRequirements::Draft] requirement=#{@requirement.id} " \
          "fell back to a templated question: #{payload['fallback_reason']}"
        )
      end
      questions = persist!(payload)
      @requirement.update!(status: "questions_drafted") if questions.any? && @requirement.status == "open"
      questions
    rescue Langgraph::UnavailableError => e
      # The requirement is already saved and the consultant can retry the draft.
      # Losing a draft is recoverable; losing the stated need would not be.
      Rails.logger.warn("[ConsultantRequirements::Draft] requirement=#{@requirement.id} #{e.message}")
      []
    end

    private

    def package_remaining
      Discovery::FollowupLimits.package_budget_remaining(@package)
    end

    def fetch_draft(allowance)
      Langgraph::Client.new.draft_requirement_questions!(
        statement: @requirement.statement,
        max_questions: allowance,
        already_asked: already_asked,
        package: package_context,
        profile: @package.conversation.blackboard["profile"] || @package.employee.profile_card,
        language: @package.employee.preferred_language.presence || @company.locale || "en"
      )
    end

    # Everything already put to this employee for this package, so the agent doesn't
    # re-ask across requirements.
    def already_asked
      @package.discovery_followup_questions.where.not(status: "superseded").pluck(:body)
    end

    def package_context
      {
        "recommendation" => @package.recommendation,
        "issues" => @package.issues.map { |i| { "title" => i.title, "body" => i.body } },
        "solutions" => @package.solutions.map { |s| { "title" => s.title, "body" => s.body } }
      }
    end

    def persist!(payload)
      next_position = (@package.discovery_followup_questions.maximum(:queue_position) || 0)
      # Drafting can legitimately run more than once for one need — on creation, and
      # again after an answer leaves it partially satisfied. Without this, each pass
      # appended another copy of the same question and the consultant saw the same
      # thing three times in their queue.
      seen = existing_bodies

      Array(payload["questions"]).filter_map do |item|
        body = item["body"].to_s.strip
        next if body.blank?
        next if seen.include?(normalize(body))

        seen << normalize(body)
        next_position += 1
        @package.discovery_followup_questions.create!(
          consultant_requirement: @requirement,
          body: body,
          rationale: item["rationale"],
          status: "drafted",
          queue_position: next_position
        )
      end
    end

    # Everything already drafted or asked for this package, so a redraft cannot
    # duplicate a question the employee has seen or is about to see.
    def existing_bodies
      @package.discovery_followup_questions
              .where.not(status: "superseded")
              .pluck(:body)
              .map { |b| normalize(b) }
              .to_set
    end

    def normalize(body)
      body.to_s.downcase.gsub(/\s+/, " ").strip
    end
  end
end
