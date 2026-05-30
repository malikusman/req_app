# frozen_string_literal: true

module Knowledge
  class IndexInsightService
    def self.call(insight:)
      new(insight: insight).call
    end

    def initialize(insight:)
      @insight = insight
      @company = insight.company
    end

    def call
      content = [@insight.summary, @insight.structured_data.to_json].join("\n").strip
      return if content.blank?

      embedding = Openai::Client.new.embedding(content)
      chunk = KnowledgeChunk.find_or_initialize_by(
        company_id: @company.id,
        source_type: "conversation_insight",
        source_id: @insight.id
      )
      chunk.assign_attributes(
        content: content.truncate(4000),
        embedding: embedding,
        embedding_model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        embedded_at: Time.current,
        metadata: {
          title: "Interview insight turn #{@insight.turn_number}",
          employee_id: @insight.employee_id,
          conversation_id: @insight.conversation_id
        }
      )
      chunk.save!
      chunk
    end
  end
end
