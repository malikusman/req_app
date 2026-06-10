# frozen_string_literal: true

module Intelligence
  class SignalExtractor
    RULES = [
      { type: "manual_process", pattern: /manual|spreadsheet|excel|copy.?paste|re-?enter/i, label: "Manual data entry and spreadsheets" },
      { type: "approval_bottleneck", pattern: /approv|sign.?off|wait.*manager|bottleneck/i, label: "Approval bottlenecks" },
      { type: "tool_dependency", pattern: /sap|salesforce|jira|slack|teams|erp|crm/i, label: "Core system dependency" },
      { type: "data_silo", pattern: /silo|disconnected|duplicate|reconcile|matching/i, label: "Data silos and reconciliation" },
      { type: "time_sink", pattern: /hours|time.?consuming|slow|tedious|repetitive/i, label: "Repetitive time-consuming work" },
      { type: "communication", pattern: /email|meeting|handoff|coordinate/i, label: "Coordination overhead" }
    ].freeze

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      texts = gather_texts
      return [] if texts.blank?

      detected = []
      RULES.each do |rule|
        hits = texts.count { |t| t.match?(rule[:pattern]) }
        next if hits.zero?

        strength = [[hits / [texts.size.to_f, 1].max, 0.35].max, 1.0].min.round(2)
        detected << {
          label: rule[:label],
          signal_type: rule[:type],
          strength: strength,
          evidence_count: hits
        }
      end

      insight_topics = ConversationInsight.where(company_id: @company.id).pluck(:structured_data)
      insight_topics.each do |data|
        (data["topics"] || []).each do |topic|
          detected << infer_from_topic(topic) if topic.present?
        end
      end

      detected.compact.uniq { |d| [d[:signal_type], d[:label]] }
    end

    private

    def gather_texts
      insight_texts = ConversationInsight.where(company_id: @company.id).pluck(:summary)
      doc_texts = @company.documents.where(status: "ready").map { |d| d.insights_preview["summary"].to_s }
      fact_texts = @company.company_memory_facts.limit(200).pluck(:content)
      message_texts = Message.joins(:conversation)
                             .where(conversations: { company_id: @company.id, status: "completed" })
                             .where(direction: "inbound")
                             .limit(200)
                             .pluck(:body)
      (insight_texts + doc_texts + fact_texts + message_texts).compact
    end

    def infer_from_topic(topic)
      RULES.find { |r| topic.match?(r[:pattern]) }&.then do |rule|
        { label: rule[:label], signal_type: rule[:type], strength: 0.45, evidence_count: 1 }
      end
    end
  end
end
