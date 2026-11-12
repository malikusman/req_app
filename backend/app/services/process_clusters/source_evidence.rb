# frozen_string_literal: true

module ProcessClusters
  class SourceEvidence
    attr_reader :source

    def initialize(source, evidence_conversations)
      @source = source
      @evidence_conversations = evidence_conversations
    end

    def fact(field, status: "known")
      entry = source.source_snapshot.dig("facts", field)
      return unless entry.is_a?(Hash) && entry["status"] == status && referenced?(entry["evidence"])

      entry
    end

    def legacy_slot(field)
      entry = source.source_snapshot[field]
      entry if entry.is_a?(Hash) && referenced?(entry["evidence"] || entry)
    end

    private

    def referenced?(anchor)
      return false unless anchor.is_a?(Hash)

      message_id = anchor["message_id"]
      turn = anchor["turn"]
      source.evidence_references.any? do |reference|
        if message_id
          reference["message_id"].to_s == message_id.to_s &&
            @evidence_conversations[reference["message_id"]] == source.conversation_id
        else
          turn && reference["message_id"].nil? && reference["turn"].to_s == turn.to_s
        end
      end
    end
  end
end
