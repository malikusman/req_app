# frozen_string_literal: true

module KeyPerson
  # Turns a finished conversation into this person's ManagementDiscoveryContext,
  # StrategicFindings and PlannedInitiatives (P04, Doc 08 §15–16). Runs once per
  # session, in the background; a later session for the same person makes a new
  # version linked to this one.
  #
  # P04 sees only this session — the person's own words, the platform's
  # captures of them, the confirmed company facts and the final coverage — never
  # another key person's conversation or anything from employees (P04 §4).
  #
  # When P04 can't be used (no model, an error, a reply that won't parse twice),
  # the context is built from the turn captures alone, marked INCOMPLETE and
  # flagged for the consultant (P04 §9). The participant is never told: they
  # have done their part (Doc 05 §16).
  class ContextBuilder
    # Where each coverage area's statements go when building from captures.
    AREA_FIELDS = {
      "STRATEGIC_OBJECTIVES" => "strategic_objectives", "GROWTH_PRIORITIES" => "growth_priorities",
      "CONCERNS" => "concerns", "BOTTLENECKS" => "operational_bottlenecks",
      "STAKEHOLDER_EXPERIENCE" => "stakeholder_friction", "PEOPLE_WORKLOAD" => "people_and_capacity",
      "SYSTEMS" => "systems_view", "REPORTING" => "reporting_gaps", "DECISIONS_APPROVALS" => "decision_structure",
      "DATA_DOCUMENTS" => "data_document_concerns", "CONSTRAINTS" => "constraints",
      "PRIORITY_AREAS" => "priority_areas", "AMBITION" => "ambition_and_missed_capability",
      "RELEASED_TIME" => "released_time_preferences"
    }.freeze

    def self.call(session, client: Openai::Client.new)
      new(session, client: client).call
    end

    def self.system_prompt
      [Openai::Client.prompt("p00a_analytical_base.v1.txt").strip,
       Openai::Client.prompt("p04_key_person_findings.v1.txt").strip].join("\n\n")
    end

    def initialize(session, client:)
      @session = session
      @participant = session.participant
      @client = client
      @pack = ContextPack.new(session)
      @turns = session.history.to_a
    end

    def call
      existing = ManagementDiscoveryContext.find_by(conversation_session_id: @session.id)
      return existing if existing

      log = RunLog.new(session: @session, stage: "P04", prompt_version: Openai::Client::KEY_PERSON_CONTEXT_PROMPT_VERSION,
                       context_classes: @pack.context_classes)
      raw, reason = from_model(log)
      if raw
        built = ContextValidator.new(raw, turn_ids: @turns.map(&:locator), transcript: @turns.map(&:text),
                                          known_names: @pack.known_names).call
        log.record!(status: log.calls > 1 ? "RETRIED" : "OK")
        save!(built, status: "COMPLETE")
      else
        log.record!(status: "FALLBACK", fallback_reason: reason)
        context = save!(from_captures, status: "INCOMPLETE", fallback_reason: reason)
        @session.update!(needs_review: true,
                         review_reasons: Array(@session.review_reasons) + [{ "type" => "CONTEXT_INCOMPLETE" }])
        context
      end
    end

    private

    def from_model(log)
      return [nil, "model_off"] unless Llm::KeyPerson.enabled? && @client.configured?
      return [nil, "model_unavailable"] if OpenaiCircuitBreaker.open?

      2.times do
        result = @client.key_person_context(system: self.class.system_prompt, context: context)
        log.add(result)
        raw = @client.parse_reply(result.content)
        return [raw, nil] if raw.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
      [nil, "unusable_reply"]
    rescue Openai::Client::Error, Timeout::Error, SystemCallError, IOError => e
      Rails.logger.warn("[KeyPerson::ContextBuilder] session=#{@session.id} #{e.class}: #{e.message}")
      [nil, "model_error"]
    end

    def context
      captures = @turns.select { |t| t.participant? && t.capture.present? }
                       .map { |t| t.capture.merge("turn_id" => t.locator) }
      transcript = @turns.map { |t| "#{t.locator} #{t.assistant? ? 'ASSISTANT' : 'PARTICIPANT'}: #{@pack.clean(t.text)}" }
      [
        @pack.participant_block, @pack.known_facts_block,
        @pack.coverage_block(@session.state_snapshot["coverage"] || {}),
        "<turn_captures trust=\"platform\">\n#{JSON.pretty_generate(captures)}\n</turn_captures>",
        "<transcript trust=\"participant\">\n#{transcript.join("\n")}\n</transcript>",
        "Build the management context now."
      ].join("\n\n")
    end

    # The record without P04: each captured statement in its area's field, the
    # initiatives and private notes as captured, and no findings or neutral
    # context — those need the whole conversation, and a wrong one would travel.
    def from_captures
      captures = @turns.select(&:participant?).filter_map(&:capture)
      fields = ContextValidator::LIST_FIELDS.index_with { [] }
      success = nil
      captures.flat_map { |c| Array(c["statements"]) }.each do |s|
        item = { "text" => s["statement"], "evidence" => [s["evidence"]] }
        if s["domain"] == "SUCCESS_DEFINITION"
          success ||= item
        elsif (field = AREA_FIELDS[s["domain"]])
          item = { "role_or_team" => s["subject_area"] || "Not stated", "preferred_focus" => s["statement"],
                   "evidence" => [s["evidence"]] } if field == "released_time_preferences"
          item["who"] = "OTHER" if field == "stakeholder_friction"
          item["type"] = "OTHER" if field == "constraints"
          fields[field] << item
        end
      end
      coverage = @session.state_snapshot["coverage"] || {}
      {
        "content" => fields.merge(
          "persona" => @participant.persona, "scope" => @pack.scope,
          "success_definition" => success || { "text" => nil, "evidence" => [] },
          "change_appetite_inferred" => { "level" => "UNCLEAR", "basis" => "", "fact_status" => "INFERRED" }
        ),
        "strategic_findings" => [],
        "planned_initiatives" => captures.flat_map { |c| Array(c["planned_initiatives"]) }.map do |i|
          { "initiative_type" => i["type"], "description" => i["description"], "timing" => i["timing"],
            "status" => "UNCERTAIN", "affected_areas" => i["affected_areas"], "evidence" => [i["evidence"]] }
        end,
        "neutral_employee_context" => [],
        "unknowns" => Coverage::AREAS.select { |a| coverage.dig(a, "status").in?([nil, "OPEN", "UNKNOWN"]) }
                                     .map { |a| { "domain" => a, "note" => "Not covered" } },
        "contradictions" => Array(@session.state_snapshot["contradictions"]).map do |c|
          { "between" => "participant vs company profile", "note" => "#{c['field']}: #{c['value']}",
            "evidence" => [c["evidence"]].compact }
        end,
        "completion" => { "domains_adequate" => Coverage::AREAS.select { |a| coverage.dig(a, "status") == "USABLE" },
                          "domains_thin" => [], "confidence" => "LOW" },
        "consultant_private" => {
          "political_context" => { "decision_makers" => [], "influencers" => [],
                                   "resistance_points" => captures.flat_map { |c| Array(c["political_signals"]) }.map do |p|
                                     { "note" => p["note"], "evidence" => [p["evidence"]] }
                                   end },
          "consultant_notes" => captures.flat_map { |c| Array(c["sensitive"]) }.map do |s|
            { "type" => "SENSITIVE", "note" => s["note"], "evidence" => [s["evidence"]] }
          end
        }
      }
    end

    def save!(built, status:, fallback_reason: nil)
      ManagementDiscoveryContext.transaction do
        previous = ManagementDiscoveryContext.where(engagement_participant_id: @participant.id).order(:version).last
        context = ManagementDiscoveryContext.create!(
          company: @session.company, engagement: @session.engagement, participant: @participant, session: @session,
          version: (previous&.version || 0) + 1, parent_version: previous, status: status,
          persona: @participant.persona, scope: @pack.scope, schema_version: ManagementDiscoveryContext::SCHEMA_VERSION,
          prompt_version: Openai::Client::KEY_PERSON_CONTEXT_PROMPT_VERSION, fallback_reason: fallback_reason,
          coverage_state: @session.state_snapshot["coverage"] || {},
          **built.slice("content", "neutral_employee_context", "unknowns", "contradictions", "completion",
                        "consultant_private").symbolize_keys
        )
        built["strategic_findings"].each do |finding|
          context.strategic_findings.create!(finding.merge("company_id" => context.company_id,
                                                           "engagement_id" => context.engagement_id))
        end
        built["planned_initiatives"].each do |initiative|
          context.planned_initiatives.create!(initiative.merge("company_id" => context.company_id,
                                                               "engagement_id" => context.engagement_id))
        end
        context
      end
    end
  end
end
