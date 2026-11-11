# frozen_string_literal: true

module TaskSources
  class SyncFromConversation
    LEGACY_SLOTS = %w[how_it_works friction friction_cost].freeze

    def self.call(conversation:)
      new(conversation).call
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
        if ledger.is_a?(Hash)
          sync_ledger(ledger)
        else
          sync_legacy(dossier["slots"] || {})
        end
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

      if latest && attributes.all? { |key, value| latest.public_send(key) == value }
        latest.update!(finding: finding) if latest.finding_id.nil? && finding
        return latest
      end

      versions.create!(**attributes, company: @conversation.company, employee: @conversation.employee,
                       finding: finding, version: (latest&.version || 0) + 1)
    end
  end
end
