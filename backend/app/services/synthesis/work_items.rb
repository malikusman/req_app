# frozen_string_literal: true

module Synthesis
  # The work employees described, in the shape consolidation compares (Doc 10
  # §3, §6; Doc 06 §5.7). Today each item is a Finding — one per role area
  # where someone described what snags — because employee discovery does not
  # yet keep WorkItem records. When it does, this is the one place that changes:
  # everything downstream reads Item, never Finding.
  #
  # Stage A, pre-normalisation, is deliberately light: the words that say which
  # work it is, and the company's known systems it mentions. The employee's own
  # wording is kept untouched beside them, because that is what the report uses.
  class WorkItems
    Item = Struct.new(:id, :finding, :employee_id, :department, :role, :title, :wording, :friction, :area,
                      :words, :title_words, :systems, :hours_min, :hours_max, :effort_type, :frequency,
                      :duration, :confidence, :single_occupant_role, :duplicate_of_id, :digest, :evidence,
                      keyword_init: true) do
      def hours? = !hours_min.nil? && !hours_max.nil?
      def waiting? = effort_type == "waiting"

      # The work and its figures as a model may read them: no names, no ids
      # beyond the item's own reference.
      def to_prompt(ref)
        {
          "ref" => ref, "role" => role, "department" => department, "title" => title,
          "what_happens_now" => wording, "what_snags" => friction, "systems" => systems,
          "how_often" => frequency, "how_long" => duration, "effort_type" => effort_type
        }.compact
      end
    end

    def self.call(company) = new(company).call

    def initialize(company)
      @company = company
      @systems = company.company_systems.active.pluck(:name).map(&:to_s).reject(&:blank?).uniq
    end

    # Live findings only: a hidden finding is out, and a merged one is already
    # represented by the finding it was merged into.
    def call
      @company.findings.live.includes(:employee).order(:id).map { |f| item(f) }
    end

    private

    def item(finding)
      text = [finding.display_title, finding.display_what_happens_now, finding.display_friction, finding.area].join(" ")
      Item.new(
        id: finding.id, finding: finding, employee_id: finding.employee_id,
        department: finding.department.presence || finding.employee&.department,
        role: finding.role_title.presence || finding.employee&.role_title,
        title: finding.display_title, wording: finding.display_what_happens_now, friction: finding.display_friction,
        area: finding.area,
        # What the work is, from how it was described. The title and the role
        # area are names, and a name alone is never evidence (Doc 10 §9.1).
        words: Findings::Words.of([finding.display_what_happens_now, finding.display_friction].join(" ")),
        title_words: Findings::Words.of([finding.display_title, finding.area].join(" ")),
        systems: @systems.select { |name| text.match?(/\b#{Regexp.escape(name)}\b/i) },
        hours_min: finding.annual_hours_min&.to_f, hours_max: finding.annual_hours_max&.to_f,
        effort_type: finding.effective_effort_type, frequency: finding.display_frequency,
        duration: finding.display_duration, confidence: finding.confidence,
        single_occupant_role: finding.single_occupant_role, duplicate_of_id: finding.possible_duplicate_of_id,
        digest: SynthesisClusterMember.digest_for(finding),
        evidence: evidence(finding)
      )
    end

    # The turns the finding was drawn from, in the shape every synthesis object
    # cites (Doc 06 §2.1 locator).
    def evidence(finding)
      refs = [{ "type" => "finding", "id" => finding.id }]
      slots = finding.evidence.is_a?(Hash) ? finding.evidence["slots"] : nil
      Array(slots&.values).compact.uniq.each do |turn|
        refs << { "type" => "employee_turn", "conversation_id" => finding.conversation_id, "turn" => turn }
      end
      refs
    end
  end
end
