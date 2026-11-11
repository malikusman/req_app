# frozen_string_literal: true

module Synthesis
  # What P11 may see, and nothing else (P11 §3–§4, §7; Doc 05 §4 "consolidation
  # and synthesis"): the company profile, coverage, the current clusters with
  # the platform's de-duplicated figures, unclustered work, each leader's
  # context and strategic findings, planned initiatives, and what people said
  # about released time.
  #
  # Never: transcripts, political context or anything else consultant-private,
  # commercial data, or a person's name — known names are replaced before the
  # text is assembled, so a name in a leader's remark never reaches the model.
  #
  # Every object the model may cite gets a short reference here (cl-12, wi_40,
  # sf_7, mc_2, pi_1); `resolve` turns a reference back into the evidence it
  # stands for, and anything else the model cites is not real.
  class ContextPack
    CONTEXT_CLASSES = %w[OTHER_EMPLOYEE_PRIVATE MANAGEMENT_STRATEGIC].freeze
    # The parts of a leadership context P11 reads (Doc 08 §16, minus the
    # consultant-private and coverage bookkeeping).
    LEADERSHIP_FIELDS = %w[strategic_objectives growth_priorities management_priorities concerns
                           operational_bottlenecks stakeholder_friction people_and_capacity systems_view
                           reporting_gaps decision_structure data_document_concerns constraints
                           ambition_and_missed_capability released_time_preferences priority_areas].freeze
    REDACTED = "a colleague"

    Figure = Struct.new(:ref, :label, :min, :max, :text, keyword_init: true)

    attr_reader :figures, :known_names, :items, :clusters, :strategic_findings, :contexts, :initiatives

    def initialize(run, items:, clusters:)
      @run = run
      @company = run.company
      @engagement = run.engagement
      @items = items
      @clusters = clusters
      @contexts = ManagementDiscoveryContext.where(engagement: @engagement).latest_per_participant
                                            .includes(:participant).order(:id).to_a
      @strategic_findings = StrategicFinding.active.where(management_discovery_context_id: @contexts.map(&:id))
                                            .order(:id).to_a
      @initiatives = PlannedInitiative.where(management_discovery_context_id: @contexts.map(&:id)).order(:id).to_a
      @known_names = known_names_for
      @refs = {}
      @figures = []
      register_refs
    end

    # The evidence a reference stands for, or nil when the model made it up.
    def resolve(ref) = @refs[ref.to_s.strip]

    def ref_for_finding(id) = "wi_#{id}"
    def ref_for_cluster(cluster) = cluster.cluster_key

    # Every figure the evidence carries: the platform's computed ranges, how
    # often and how long people said, and what leadership and the planned
    # initiatives said — with number words as digits too, so "in three months"
    # allows "3 months" without allowing anything new.
    def allowed_numbers
      @allowed_numbers ||= begin
        sources = @figures.map(&:text) + item_phrases + leadership_phrases
        Llm::GroundedNumbers.allowed_numbers(sources + sources.map { |s| digits(s) })
      end
    end

    NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve].each_with_index.to_h.freeze

    # The figure a quoted capacity reference matches exactly — quoted whole, or
    # with the same lower and upper bound and no other number — or nil.
    def figure_matching(text)
      quoted = @figures.find { |f| text.to_s.include?(f.text) }
      return quoted if quoted

      numbers = text.to_s.scan(/\d[\d,]*(?:\.\d+)?/).map { |n| n.delete(",").to_f }.uniq.sort
      return nil if numbers.empty?

      @figures.find { |f| [f.min, f.max].uniq.sort == numbers }
    end

    def names_someone?(text)
      @known_names.any? { |name| text.to_s.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i) }
    end

    def context
      [
        block("company_profile", company_profile),
        block("coverage", coverage),
        block("process_clusters", @clusters.map { |c| cluster_json(c) }),
        block("effort_normalisation", @figures.select { |f| f.ref.start_with?("cl-") }.map { |f| figure_json(f) }),
        block("work_items", unclustered.map { |i| item_json(i) }),
        block("invisible_work", "None captured separately; see what_snags on each work item."),
        block("management_contexts", @contexts.map { |c| leadership_json(c) }),
        block("planned_initiatives", @initiatives.map { |i| initiative_json(i) }),
        block("document_findings", "None provided."),
        block("posture_signals", "None captured."),
        block("role_potential", role_potential),
        "Produce the synthesis now."
      ].join("\n\n")
    end

    private

    def block(name, value)
      body = value.is_a?(String) ? value : JSON.pretty_generate(value)
      %(<#{name} trust="platform">\n#{redact(body)}\n</#{name}>)
    end

    def register_refs
      @items.each do |item|
        @refs[ref_for_finding(item.id)] = { "type" => "finding", "id" => item.id }
        next unless item.hours?

        @figures << Figure.new(ref: ref_for_finding(item.id), label: item.title, min: item.hours_min,
                               max: item.hours_max,
                               text: "#{item.title}: #{range(item.hours_min, item.hours_max)} hours per year")
      end
      @clusters.each do |cluster|
        @refs[ref_for_cluster(cluster)] = { "type" => "cluster", "key" => cluster.cluster_key,
                                            "version" => cluster.version }
        normalization = cluster.effort_normalization
        next unless normalization&.hours?

        @figures << Figure.new(ref: cluster.cluster_key, label: cluster.name, min: normalization.hours_min.to_f,
                               max: normalization.hours_max.to_f,
                               text: "#{cluster.name}: #{range(normalization.hours_min, normalization.hours_max)} " \
                                     "hours per year (de-duplicated)")
      end
      @contexts.each { |c| @refs["mc_#{c.id}"] = { "type" => "management_context", "id" => c.id, "version" => c.version } }
      @strategic_findings.each do |sf|
        @refs["sf_#{sf.id}"] = { "type" => "strategic_finding", "id" => sf.id, "version" => sf.version }
      end
      @initiatives.each { |i| @refs["pi_#{i.id}"] = { "type" => "planned_initiative", "id" => i.id } }
    end

    def clustered_ids = @clustered_ids ||= @clusters.flat_map(&:finding_ids).to_set
    def unclustered = @items.reject { |i| clustered_ids.include?(i.id) }

    def company_profile
      profile = @company.company_profile || {}
      {
        "industry" => profile["industry"], "business_model" => profile["business_model"],
        "departments" => Array(profile["org_departments"]), "locations" => profile["locations"],
        "systems" => @company.company_systems.active.order(:name).limit(30).pluck(:name)
      }.compact
    end

    def coverage
      covered = @items.map(&:department).compact.map(&:strip).uniq
      planned = Array(@engagement.planned_departments).filter_map { |row| row["name"].presence }
      {
        "people_interviewed" => @items.map(&:employee_id).compact.uniq.size,
        "work_items" => @items.size, "clusters" => @clusters.size,
        "departments_covered" => covered,
        "departments_planned_not_covered" => planned.reject { |d| covered.any? { |c| c.casecmp?(d) } },
        "leadership_contexts" => @contexts.size
      }
    end

    def cluster_json(cluster)
      by_id = @items.index_by(&:id)
      members = cluster.finding_ids.filter_map { |id| by_id[id] }
      {
        "ref" => cluster.cluster_key, "name" => cluster.name, "type" => cluster.cluster_type,
        "status" => cluster.status == "APPROVED" ? "APPROVED" : "PROVISIONAL",
        "departments" => cluster.departments, "roles" => cluster.roles,
        "systems" => members.flat_map(&:systems).uniq,
        "members" => members.map { |i| { "ref" => ref_for_finding(i.id), "role" => i.role, "department" => i.department,
                                         "title" => i.title } },
        "variants" => Array(cluster.variants).map do |v|
          v.slice("label", "roles", "departments", "distinguishing_factors", "material_differences")
        end,
        "single_participant" => cluster.single_member
      }
    end

    def figure_json(figure)
      cluster = @clusters.find { |c| c.cluster_key == figure.ref }
      n = cluster&.effort_normalization
      { "cluster" => figure.ref, "figure" => figure.text, "conservative" => n&.conservative_adjustment,
        "double_count_warning" => n&.double_count_warning }.compact
    end

    def item_json(item)
      figure = @figures.find { |f| f.ref == ref_for_finding(item.id) }
      item.to_prompt(ref_for_finding(item.id)).merge("effort" => figure&.text || "Not quantified")
    end

    def leadership_json(context)
      content = context.content || {}
      fields = LEADERSHIP_FIELDS.to_h { |field| [field, Array(content[field]).filter_map { |entry| line(entry) }] }
                                .reject { |_, lines| lines.empty? }
      {
        "ref" => "mc_#{context.id}", "persona" => context.persona, "scope" => context.scope,
        "success_definition" => line(content["success_definition"]),
        **fields,
        "strategic_findings" => @strategic_findings.select { |sf| sf.management_discovery_context_id == context.id }
                                                   .map { |sf| strategic_finding_json(sf) }
      }.compact
    end

    def strategic_finding_json(finding)
      {
        "ref" => "sf_#{finding.id}", "statement" => finding.statement, "category" => finding.category,
        "scope" => finding.scope, "symptom_or_cause" => finding.symptom_or_cause,
        "business_consequence" => finding.business_consequence,
        "management_importance" => finding.management_importance, "validation_need" => finding.validation_need,
        "related_departments" => finding.related_departments, "related_systems" => finding.related_systems,
        "planned_initiative_link" => finding.planned_initiative_link
      }.compact
    end

    def initiative_json(initiative)
      { "ref" => "pi_#{initiative.id}", "type" => initiative.initiative_type, "description" => initiative.description,
        "timing" => initiative.timing, "status" => initiative.status, "affected_areas" => initiative.affected_areas }
        .compact
    end

    # What people and leadership said about released time, by role — never by
    # person: notes from a role one person holds are already pooled away.
    def role_potential
      staff = Findings::ForReport.new(company: @company).role_potential_notes
      leadership = @contexts.flat_map do |context|
        Array((context.content || {})["released_time_preferences"]).filter_map do |entry|
          next unless entry.is_a?(Hash) && entry["preferred_focus"].present?

          { "role_or_team" => entry["role_or_team"], "preferred_focus" => entry["preferred_focus"],
            "source" => "MANAGEMENT" }
        end
      end
      staff.map { |row| row.merge("source" => "PARTICIPANT") } + leadership
    end

    # A leadership entry as text, whatever shape P04 gave it.
    def line(entry)
      case entry
      when String then entry.presence
      when Hash
        if entry["preferred_focus"].present?
          [entry["role_or_team"], entry["preferred_focus"]].compact.join(": ")
        else
          entry["text"].presence || entry["statement"].presence || entry["note"].presence
        end
      end
    end

    def item_phrases = @items.flat_map { |i| [i.frequency, i.duration, i.wording, i.friction] }.compact

    def leadership_phrases
      @strategic_findings.flat_map { |sf| [sf.statement, sf.business_consequence] }.compact +
        @initiatives.flat_map { |i| [i.description, i.timing] }.compact
    end

    def digits(text)
      text.to_s.gsub(/\b(#{NUMBER_WORDS.keys.join('|')})\b/i) { |w| NUMBER_WORDS[w.downcase].to_s }
    end

    def redact(text)
      @known_names.sort_by { |n| -n.length }.reduce(text) do |out, name|
        out.gsub(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/i, REDACTED)
      end
    end

    def known_names_for
      names = @engagement.participants.pluck(:name) + [@engagement.key_user&.name] +
              @company.employees.pluck(:display_name) + @company.company_users.pluck(:name)
      names.compact.flat_map { |n| [n, n.split.first] }.map { |n| n.to_s.strip }.select { |n| n.length >= 3 }
           .reject { |n| n.match?(/\A(test|employee|participant|user)\z/i) }.uniq
    end

    def range(min, max)
      low = number(min)
      high = number(max)
      low == high ? low : "#{low}–#{high}"
    end

    def number(value)
      value = value.to_f
      value == value.round ? value.round.to_s : value.round(1).to_s
    end
  end
end
