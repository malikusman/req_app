# frozen_string_literal: true

module KeyPerson
  # Keeps only what P04 may say (P04 §10). The model organises the conversation;
  # code decides what is kept:
  #
  #   - every item cites turns that exist in this session, or it goes;
  #   - fact status is REPORTED or INFERRED; change appetite is always INFERRED;
  #   - no finding names a person, invents a figure, or proposes a solution;
  #   - neutral context for staff loses any line that attributes a view to
  #     management, names someone, suggests a solution or carries a number;
  #   - political context and consultant notes go to the consultant-only part.
  class ContextValidator
    LIST_FIELDS = %w[strategic_objectives growth_priorities management_priorities concerns operational_bottlenecks
                     stakeholder_friction people_and_capacity systems_view reporting_gaps decision_structure
                     data_document_concerns constraints ambition_and_missed_capability released_time_preferences
                     priority_areas].freeze
    # P04's own example uses DECISIONS_APPROVALS, which isn't in its category list.
    CATEGORY_ALIASES = { "DECISIONS_APPROVALS" => "GOVERNANCE", "APPROVALS" => "GOVERNANCE",
                         "PEOPLE" => "ORGANISATION", "SYSTEMS" => "SYSTEM" }.freeze
    WHO = %w[CUSTOMERS SUPPLIERS EMPLOYEES MANAGEMENT OTHER].freeze
    CONSTRAINT_TYPES = %w[TIMING SECURITY REGULATORY CULTURAL ORGANISATIONAL OTHER].freeze
    APPETITE = %w[HIGH MODERATE CAUTIOUS UNCLEAR].freeze
    NOTE_TYPES = %w[SENSITIVE FOLLOW_UP OBSERVATION].freeze
    CONFIDENCE = %w[HIGH MEDIUM LOW].freeze
    INITIATIVE_STATUSES = PlannedInitiative::STATUSES

    # A finding that tells the client what to do, rather than what is wrong.
    SOLUTION = /\b(should|recommend\w*|needs? (an?|to (buy|implement|adopt|deploy))|implement\w*|deploy\w*|
                introduc\w*|install\w*|adopt\w*)\b.*\b(ai|agents?|chatbots?|automation|automate\w*|tools?|
                software|platform|app)\b/xi
    # Neutral context must not say who thinks what, or what is wrong (P04 rule 13).
    ATTRIBUTION = Regexp.union(
      /\b(management|managers?|owner|ceo|md|cfo|coo|leadership|director|the boss|head of|thinks?|believes?|feels?|
         says?|said|complain\w*|blames?|frustrat\w*|criticis\w*|unhappy|slow|inefficien\w*|lazy|poor|weak|
         struggl\w*|problem|fail\w*)\b/xi,
      /الإدارة|المدير|الرئيس التنفيذي|المالك|يعتقد|يقول|يشتكي|بطيء|ضعيف|مشكلة/
    )

    def initialize(raw, turn_ids:, transcript:, known_names: [])
      @raw = raw.is_a?(Hash) ? raw : {}
      @turn_ids = turn_ids.to_set
      @allowed_numbers = Llm::GroundedNumbers.allowed_numbers(transcript)
      @names = Array(known_names)
    end

    def call
      context = @raw["management_context"].is_a?(Hash) ? @raw["management_context"] : {}
      {
        "content" => content(context),
        "strategic_findings" => findings,
        "planned_initiatives" => initiatives,
        "neutral_employee_context" => neutral_context,
        "unknowns" => list(@raw["unknowns"]).filter_map do |u|
          { "domain" => text(u["domain"]), "note" => text(u["note"]) } if u["note"].present?
        end,
        "contradictions" => cited(@raw["contradictions"]).map do |c|
          { "between" => text(c["between"]), "note" => text(c["note"]), "evidence" => c["evidence"] }
        end.select { |c| c["note"].present? },
        "completion" => completion,
        "consultant_private" => consultant_private
      }
    end

    private

    def content(context)
      fields = LIST_FIELDS.to_h { |field| [field, cited(context[field]).filter_map { |item| item_for(field, item) }] }
      success = context["success_definition"].is_a?(Hash) ? context["success_definition"] : {}
      success_evidence = evidence(success["evidence"])
      appetite = context["change_appetite_inferred"].is_a?(Hash) ? context["change_appetite_inferred"] : {}
      fields.merge(
        "persona" => text(context["persona"]), "scope" => text(context["scope"]),
        "success_definition" => if success["text"].present? && success_evidence.any?
                                  { "text" => text(success["text"]), "evidence" => success_evidence }
                                else
                                  { "text" => nil, "evidence" => [] }
                                end,
        "change_appetite_inferred" => { "level" => enum(appetite["level"], APPETITE, "UNCLEAR"),
                                        "basis" => text(appetite["basis"]), "fact_status" => "INFERRED" }
      )
    end

    def item_for(field, item)
      case field
      when "released_time_preferences"
        return nil if item["preferred_focus"].blank?

        { "role_or_team" => text(item["role_or_team"]).presence || "Not stated",
          "preferred_focus" => text(item["preferred_focus"]), "evidence" => item["evidence"] }
      else
        return nil if item["text"].blank?

        entry = { "text" => text(item["text"]), "evidence" => item["evidence"] }
        case field
        when "strategic_objectives" then entry["horizon"] = text(item["horizon"]).presence
        when "management_priorities" then entry["rank"] = item["rank"].is_a?(Integer) ? item["rank"] : nil
        when "concerns" then entry["consequence"] = text(item["consequence"]).presence
        when "operational_bottlenecks" then entry["area"] = text(item["area"]).presence
        when "stakeholder_friction" then entry["who"] = enum(item["who"], WHO, "OTHER")
        when "constraints" then entry["type"] = enum(item["type"], CONSTRAINT_TYPES, "OTHER")
        end
        entry
      end
    end

    def findings
      cited(@raw["strategic_findings"]).filter_map do |f|
        statement = text(f["statement"])
        next if statement.blank?
        next if names_someone?("#{statement} #{f['business_consequence']}")
        next if statement.match?(SOLUTION)
        next unless Llm::GroundedNumbers.grounded?("#{statement} #{f['business_consequence']}", @allowed_numbers)

        category = f["category"].to_s.upcase
        category = CATEGORY_ALIASES.fetch(category, category)
        {
          "category" => StrategicFinding::CATEGORIES.include?(category) ? category : "OTHER",
          "scope" => enum(f["scope"], StrategicFinding::SCOPES, "COMPANY"),
          "statement" => statement,
          "business_consequence" => text(f["business_consequence"]).presence,
          "symptom_or_cause" => enum(f["symptom_or_cause"], StrategicFinding::SYMPTOM_OR_CAUSE, "SYMPTOM"),
          "source_basis" => enum(f["source_basis"], StrategicFinding::SOURCE_BASES, "MANAGEMENT_STATEMENT"),
          "fact_status" => enum(f["fact_status"], StrategicFinding::FACT_STATUSES, "REPORTED"),
          "management_importance" => enum(f["management_importance"], StrategicFinding::IMPORTANCE, "MEDIUM"),
          "related_departments" => strings(f["related_departments"]),
          "related_systems" => strings(f["related_systems"]),
          "planned_initiative_link" => text(f["planned_initiative_link"]).presence,
          "validation_need" => text(f["validation_need"]).presence,
          "evidence" => f["evidence"]
        }
      end
    end

    def initiatives
      cited(@raw["planned_initiatives"]).filter_map do |i|
        next if i["description"].blank?

        { "initiative_type" => enum(i["type"], PlannedInitiative::TYPES, "OTHER"),
          "description" => text(i["description"]), "timing" => text(i["timing"]).presence,
          "status" => enum(i["status"], INITIATIVE_STATUSES, "UNCERTAIN"),
          "affected_areas" => strings(i["affected_areas"]), "evidence" => i["evidence"] }
      end
    end

    def neutral_context
      list(@raw["neutral_context_for_employee_discovery"]).filter_map do |n|
        department = text(n["department"])
        line = text(n["context"]).truncate(300)
        next if department.blank? || line.blank?
        next if line.match?(ATTRIBUTION) || line.match?(/\d/) || names_someone?(line)
        next if Guard.blocked_term(line, "QUESTION", "")

        { "department" => department, "context" => line }
      end
    end

    def completion
      raw = @raw["completion"].is_a?(Hash) ? @raw["completion"] : {}
      {
        "domains_adequate" => strings(raw["domains_adequate"]) & Coverage::AREAS,
        "domains_thin" => strings(raw["domains_thin"]) & Coverage::AREAS,
        "confidence" => enum(raw["confidence"], CONFIDENCE, "LOW")
      }
    end

    def consultant_private
      political = @raw["political_context"].is_a?(Hash) ? @raw["political_context"] : {}
      {
        "political_context" => %w[decision_makers influencers resistance_points].to_h do |key|
          [key, cited(political[key]).filter_map { |p| { "note" => text(p["note"]), "evidence" => p["evidence"] } if p["note"].present? }]
        end,
        "consultant_notes" => cited(@raw["consultant_notes"]).filter_map do |n|
          next if n["note"].blank?

          { "type" => enum(n["type"], NOTE_TYPES, "OBSERVATION"), "note" => text(n["note"]), "evidence" => n["evidence"] }
        end
      }
    end

    # Items with at least one real turn, keeping only the real ones.
    def cited(value)
      list(value).filter_map do |item|
        refs = evidence(item["evidence"])
        item.merge("evidence" => refs) if refs.any?
      end
    end

    def evidence(value) = Array(value).map(&:to_s).select { |ref| @turn_ids.include?(ref) }.uniq

    def names_someone?(value)
      @names.any? { |name| value.to_s.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i) }
    end

    def list(value) = Array(value).select { |v| v.is_a?(Hash) }
    def strings(value) = Array(value).map { |v| text(v) }.reject(&:blank?).uniq
    def text(value) = value.to_s.squish.truncate(600)

    def enum(value, allowed, default)
      candidate = value.to_s.strip.upcase
      allowed.include?(candidate) ? candidate : default
    end
  end
end
