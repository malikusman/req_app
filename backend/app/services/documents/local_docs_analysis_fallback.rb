# frozen_string_literal: true

module Documents
  # Used when LangGraph is down or unconfigured — still produces usable KB + questions.
  class LocalDocsAnalysisFallback
    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = payload.to_h.deep_stringify_keys
    end

    def call
      docs = Array(@payload["documents"])
      profile = @payload["company_profile"] || {}
      knowledge = []
      questions = []
      summaries = []

      docs.each do |doc|
        text = doc["text_excerpt"].to_s
        next if text.blank?

        title = "#{doc['filename']} — key points"
        knowledge << {
          "entry_type" => infer_type(doc),
          "title" => title.truncate(120),
          "content" => text.truncate(1200),
          "confidence" => 0.55,
          "department" => doc["department"],
          "source_document_ids" => [doc["id"]],
          "source_chunk_ids" => Array(doc["chunk_ids"]).first(5)
        }
        summaries << { "document_id" => doc["id"], "summary" => text.truncate(280) }
      end

      goals = Array(profile.dig("questionnaire_answers", "primary_goals")).presence ||
              Array(profile.dig("company_profile", "business_goals"))
      if goals.any? && knowledge.any?
        questions << {
          "body" => "How do your current documents and processes support these goals: #{goals.first(3).join(', ')}?",
          "rationale" => "Profile goals vs uploaded documentation"
        }
      end
      if docs.none? { |d| d["document_type"].to_s.in?(%w[sop policy process]) }
        questions << {
          "body" => "Can you share a written SOP or policy for your most critical operational workflow?",
          "rationale" => "Missing process documentation"
        }
      end
      if profile.dig("questionnaire_answers", "erp_system").blank? && knowledge.none? { |k| k["entry_type"] == "system" }
        questions << {
          "body" => "Which core systems (ERP, CRM, accounting) does your team rely on day to day?",
          "rationale" => "Systems not evident from documents or profile"
        }
      end

      {
        "knowledge_entries" => knowledge,
        "questions" => questions.first(8),
        "document_summaries" => summaries,
        "summary" => "Local fallback analysis of #{docs.size} document(s).",
        "events" => [
          { "agent" => "local_fallback", "message" => "Generated KB without LangGraph" }
        ]
      }
    end

    private

    def infer_type(doc)
      ct = doc["content_type"].to_s
      dt = doc["document_type"].to_s
      return "metric" if ct.include?("spreadsheet") || doc["filename"].to_s.end_with?(".xlsx", ".csv")
      return "policy" if dt == "policy"
      return "process" if dt.in?(%w[sop process])
      return "system" if doc["filename"].to_s.downcase.match?(/erp|sap|crm|oracle/)

      "other"
    end
  end
end
