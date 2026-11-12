# frozen_string_literal: true

module DeepDivePlans
  class Context
    FIELDS = TaskIntelligence::EvaluateCluster::FIELDS
    LEGACY = { "steps_decisions" => "how_it_works", "bottlenecks" => "friction" }.freeze

    def initialize(run, selection, task)
      @run, @selection, @task = run, selection, task
    end

    def call
      evidence = TaskSelection::Evidence.new(@run)
      sources = TaskSource.where(company_id: @run.company_id, id: @task.fetch("source_ids")).index_by(&:id)
      message_ids = sources.values.flat_map { |source| source.evidence_references.pluck("message_id") }.compact
      anchors = TaskSource.evidence_messages.where(id: message_ids).pluck(:id, :conversation_id).to_h
      relationships = evidence.relationships_with_current_requests.select { |pair| pair.fetch("source_ids").intersect?(sources.keys) }
      {
        "company_id" => @run.company_id, "run_id" => @run.id, "selection_revision_id" => @selection.id,
        "language" => @run.company.locale.presence || "en",
        "selection_version" => @selection.version, "task_id" => @task.fetch("id"), "title" => @task.fetch("title"),
        "proposal_ids" => @task.fetch("proposal_ids"), "origin_task_ids" => @task.fetch("origin_task_ids", []),
        "cluster_revision_ids" => @task.fetch("cluster_revision_ids"), "gaps" => @task.fetch("gaps"),
        "consultant_notes" => @task.fetch("notes", []),
        "effort" => @task.slice("effective_effort", "effort_assumptions"),
        "participants" => participants,
        "sources" => @task.fetch("source_versions").map do |link|
          source = sources.fetch(link.fetch("id"))
          if source.version != link.fetch("version") || source.conversation_id != link.fetch("conversation_id") ||
             source.employee_id != link.fetch("employee_id")
            raise ActiveRecord::RecordNotFound
          end

          link.merge("name" => source.name, "facts" => facts(source, anchors),
                     "effort_observations" => evidence.sources.fetch(source.id).fetch("effort_observations"),
                     "finding_id" => source.finding_id)
        end,
        "relationships" => relationships.map { |pair| pair.except("current_clarification_request", "clarification_request") },
        "relationship_judgments" => @selection.snapshot.dig("final_selection", "relationship_overrides").to_h.values.select do |pair|
          pair.fetch("source_ids").intersect?(sources.keys)
        end,
        "open_clarifications" => relationships.filter_map do |pair|
          request = pair["current_clarification_request"]
          request.merge("source_ids" => pair.fetch("source_ids")) if request&.fetch("status") == "open"
        end.uniq { |request| request.fetch("id") }
      }
    end

    private

    def participants
      employees = Employee.where(company_id: @run.company_id, id: @task.fetch("participant_ids")).index_by(&:id)
      @task.fetch("participant_ids").map do |id|
        employee = employees[id]
        eligible = employee && employee.participation_status != "declined"
        details = eligible ? employee.as_json(only: %i[display_name role_title department]) : {}
        details.merge("id" => id, "eligible" => !!eligible, "discovery_consent_recorded" => !!(eligible && employee.consent_given_at))
      end
    end

    def facts(source, anchors)
      evidence = ProcessClusters::SourceEvidence.new(source, anchors)
      FIELDS.filter_map do |field|
        fact = evidence.fact(field) || (evidence.legacy_slot(LEGACY[field]) if LEGACY.key?(field))
        value = fact&.fetch("value", nil)
        next unless value.is_a?(String) && value.present?

        { "field" => field, "reported_value" => value.first(1_000),
          "reference" => (fact["evidence"] || fact).slice("message_id", "turn") }
      end
    end
  end
end
