# frozen_string_literal: true

module TaskSources
  # These rows are the work items synthesis should compare too; it reads
  # Findings until then (Synthesis::WorkItems) (docs/CONSOLIDATION_ENGINES.md §9).
  class SyncFromConversation
    LEGACY_SLOTS = %w[how_it_works friction friction_cost].freeze

    def self.call(conversation:)
      new(conversation).call
    end

    # Ignore summary, confirmation, timing and other interview state that does
    # not change the recorded activities.
    def self.evidence_input(snapshot)
      dossier = snapshot&.dig("blackboard", "dossier") || {}
      ledger = dossier["workflow"]
      return ["workflow_ledger", ledger["tasks"]] if ledger.is_a?(Hash) && ledger["tasks"].present?
      return if ledger.is_a?(Hash)

      return unless dossier["slots"].is_a?(Hash)

      slots = dossier["slots"].select do |key, _|
        slot, _, area = key.partition("::")
        LEGACY_SLOTS.include?(slot) && area.present?
      end
      ["legacy_slots", slots] if slots.present?
    end

    def initialize(conversation)
      @conversation = conversation
    end

    def call
      # Reload under the row lock so competing jobs read the same current ledger
      # and cannot allocate the same next version.
      @conversation.with_lock do
        dossier = @conversation.dossier
        ledger = dossier["workflow"]
        sources = ledger.is_a?(Hash) ? sync_ledger(ledger) : sync_legacy(dossier["slots"] || {})
        retired = retire_missing(sources)
        if retired || sources.any?(&:previously_new_record?)
          TaskEvidenceRefresh.record_source_change(@conversation.id)
        end
        sources
      end
    end

    private

    def sync_ledger(ledger)
      revision = nonnegative_integer(ledger["revision"])
      tasks = Array(ledger["tasks"]).select do |task|
        task.is_a?(Hash) && task["id"].is_a?(String) &&
          task["id"].present? && task["id"].length <= 255 &&
          task["name"].is_a?(String) && task["name"].present?
      end
      duplicate_ids = tasks.map { |task| task["id"] }.tally.select { |_, count| count > 1 }.keys

      tasks.filter_map do |task|
        next if duplicate_ids.include?(task["id"])

        references = eligible_references(task)
        name_references = evidence_references(task["evidence"])
        next if name_references.any? && (name_references & references).empty?

        facts = task["facts"].is_a?(Hash) ? task["facts"].values.grep(Hash) : []
        current_evidence = [task["evidence"], *facts.filter_map { |fact| fact["evidence"] }]
        next if (evidence_references(current_evidence) & references).empty?

        steps = task["facts"].is_a?(Hash) ? task["facts"]["steps_decisions"] : nil
        description = if steps.is_a?(Hash) && steps["status"] == "known" &&
                         (evidence_references(steps["evidence"]) & references).any?
                        steps["value"]
                      end
        persist("workflow_ledger", task["id"], task["name"], description, revision, task, references)
      end
    end

    def sync_legacy(slots)
      return [] unless slots.is_a?(Hash)

      by_area = slots.each_with_object({}) do |(key, entry), areas|
        slot, _, area = key.partition("::")
        next unless LEGACY_SLOTS.include?(slot) && area.present? && area.length <= 255
        next unless entry.is_a?(Hash) && entry["value"].is_a?(String) && entry["value"].present?
        next unless entry["confidence"].is_a?(Numeric) &&
                    entry["confidence"] >= Findings::BuildFromConversation::THRESHOLD

        (areas[area] ||= {})[slot] = entry
      end

      by_area.filter_map do |area, entries|
        references = eligible_references(entries)
        # A timed cost alone or a role-area label alone does not establish the activity.
        description_slot = %w[how_it_works friction].find do |slot|
          (evidence_references(entries[slot]) & references).any?
        end
        next unless description_slot

        persist("legacy_slots", area, area, entries[description_slot]["value"], nil, entries, references)
      end
    end

    def eligible_references(snapshot)
      references = evidence_references(snapshot).uniq
      message_ids = references.filter_map { |reference| reference["message_id"] }
      allowed_ids = TaskSource.evidence_messages.where(conversation_id: @conversation.id, id: message_ids)
                              .pluck(:id).to_set
      references.select { |reference| !reference.key?("message_id") || allowed_ids.include?(reference["message_id"]) }
    end

    def evidence_references(value)
      case value
      when Array
        value.flat_map { |entry| evidence_references(entry) }
      when Hash
        message_id = nonnegative_integer(value["message_id"])
        turn = nonnegative_integer(value["turn"])
        refs = value.values.flat_map { |entry| evidence_references(entry) }
        if message_id&.positive? || (refs.empty? && value["message_id"].nil? && turn)
          refs << { "message_id" => message_id, "turn" => turn }.compact
        end
        refs
      else
        []
      end
    end

    def nonnegative_integer(value)
      number = Integer(value.to_s, 10, exception: false)
      number if number && number >= 0
    end

    def persist(kind, local_id, name, description, revision, snapshot, references)
      versions = @conversation.task_sources.where(source_kind: kind, local_task_id: local_id)
      latest = versions.order(version: :desc).first
      finding = Finding.find_by(company_id: @conversation.company_id, employee_id: @conversation.employee_id,
                                conversation_id: @conversation.id,
                                source_key: Finding.discovery_source_key(conversation_id: @conversation.id, area: name))
      attributes = { name: name, description: description, discovery_revision: revision,
                     source_snapshot: snapshot, evidence_references: references }

      if latest && !latest.retired? && latest.finding_id == finding&.id &&
         attributes.except(:discovery_revision).all? { |key, value| latest.public_send(key) == value }
        return latest
      end

      versions.create!(**attributes, company: @conversation.company, employee: @conversation.employee,
                       finding: finding, version: (latest&.version || 0) + 1)
    end

    def retire_missing(sources)
      active_ids = sources.map(&:id).to_set
      latest = @conversation.task_sources.select("DISTINCT ON (source_kind, local_task_id) task_sources.*")
                            .order(:source_kind, :local_task_id, version: :desc)
      missing = latest.reject { |source| source.retired? || active_ids.include?(source.id) }
      missing.each do |source|
        retirement = source.dup
        retirement.assign_attributes(retired: true, version: source.version + 1, evidence_references: [])
        retirement.save!
      end
      missing.any?
    end
  end
end
