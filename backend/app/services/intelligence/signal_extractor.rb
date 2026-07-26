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

    MAX_EVIDENCE = 10
    MAX_CHUNKS_PER_DOC = 8
    CHUNK_TRUNCATE = 500

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      texts = gather_texts
      message_sources = gather_message_sources
      multimodal = gather_multimodal_sources
      return [] if texts.blank? && multimodal.blank? && message_sources.blank?

      detected = []
      RULES.each do |rule|
        text_hits = texts.count { |t| t.match?(rule[:pattern]) }
        source_excerpts = message_evidence_for(rule, message_sources)
        evidence = multimodal_evidence_for(rule, multimodal)
        total_hits = text_hits + evidence.size + source_excerpts.size
        next if total_hits.zero?

        strength = [[total_hits / [texts.size.to_f + multimodal.size + message_sources.size, 1].max, 0.35].max, 1.0].min.round(2)
        detected << {
          label: rule[:label],
          signal_type: rule[:type],
          strength: strength,
          evidence_count: total_hits,
          multimodal_evidence: evidence,
          source_excerpts: source_excerpts
        }
      end

      insight_topics = ConversationInsight.where(company_id: @company.id).pluck(:structured_data)
      insight_topics.each do |data|
        (data["topics"] || []).each do |topic|
          inferred = infer_from_topic(topic)
          detected << inferred if inferred.present?
        end
      end

      detected.compact.uniq { |d| [d[:signal_type], d[:label]] }
    end

    private

    def gather_texts
      insight_texts = ConversationInsight.where(company_id: @company.id).pluck(:summary)
      doc_texts = @company.documents.where(status: "ready").flat_map { |d| document_text_blobs(d) }
      fact_texts = @company.company_memory_facts.limit(200).pluck(:content)
      message_texts = gather_message_sources.map { |m| m[:body] }
      knowledge_texts = gather_knowledge_texts
      (insight_texts + doc_texts + fact_texts + message_texts + knowledge_texts).compact_blank
    end

    def gather_knowledge_texts
      return [] unless @company.respond_to?(:company_knowledge_entries)

      @company.company_knowledge_entries.active.limit(200).map do |entry|
        [entry.entry_type, entry.title, entry.content.to_s.truncate(600), entry.department].compact.join(" ")
      end
    end

    def document_text_blobs(document)
      preview = document.insights_preview.is_a?(Hash) ? document.insights_preview : {}
      preview_blobs = [
        preview["summary"].to_s,
        Array(preview["friction_points"]).join(" "),
        Array(preview["workflows"]).join(" "),
        Array(preview["tools_mentioned"]).join(" "),
        Array(preview["systems"]).join(" ")
      ]
      chunk_blobs = document.document_chunks.order(:chunk_index).limit(MAX_CHUNKS_PER_DOC).pluck(:content).map do |content|
        content.to_s.truncate(CHUNK_TRUNCATE)
      end
      (preview_blobs + chunk_blobs).compact_blank
    end

    def gather_message_sources
      @message_sources ||= Message.joins(:conversation)
                                  .includes(conversation: :employee)
                                  .where(conversations: { company_id: @company.id, status: "completed" })
                                  .where(direction: "inbound")
                                  .where.not(body: [nil, ""])
                                  .order(created_at: :desc)
                                  .limit(200)
                                  .map do |message|
        {
          message_id: message.id,
          employee_id: message.conversation.employee_id,
          conversation_id: message.conversation_id,
          body: message.body.to_s
        }
      end
    end

    def message_evidence_for(rule, message_sources)
      message_sources.filter_map do |source|
        next unless source[:body].match?(rule[:pattern])

        {
          message_id: source[:message_id],
          employee_id: source[:employee_id],
          conversation_id: source[:conversation_id],
          excerpt: source[:body].truncate(200)
        }
      end.first(MAX_EVIDENCE)
    end

    def gather_multimodal_sources
      MediaAttachment.where(company_id: @company.id, status: "ready").includes(:employee).filter_map do |attachment|
        excerpts = multimodal_excerpts(attachment)
        matching_types = RULES.filter_map do |rule|
          rule[:type] if excerpts.any? { |text| text.match?(rule[:pattern]) }
        end
        next if matching_types.empty?

        {
          attachment: attachment,
          excerpts: excerpts,
          matching_types: matching_types
        }
      end
    end

    def multimodal_excerpts(attachment)
      insights = attachment.structured_insights.presence || {}
      [
        attachment.caption,
        attachment.extracted_text,
        insights["summary"],
        *Array(insights["pain_points"]),
        *Array(insights["friction_points"]),
        *Array(insights["tools_visible"]),
        *Array(insights["process_steps"]),
        *Array(insights["workflows"])
      ].compact.map(&:to_s).reject(&:blank?)
    end

    def multimodal_evidence_for(rule, multimodal)
      multimodal.filter_map do |source|
        next unless source[:matching_types].include?(rule[:type])

        attachment = source[:attachment]
        excerpt = source[:excerpts].find { |text| text.match?(rule[:pattern]) } || source[:excerpts].first
        {
          source: "media_attachment",
          id: attachment.id,
          attachment_type: attachment.attachment_type,
          conversation_id: attachment.conversation_id,
          excerpt: excerpt.to_s.truncate(200),
          confidence: attachment.confidence
        }
      end
    end

    def infer_from_topic(topic)
      RULES.find { |r| topic.match?(r[:pattern]) }&.then do |rule|
        { label: rule[:label], signal_type: rule[:type], strength: 0.45, evidence_count: 1, multimodal_evidence: [], source_excerpts: [] }
      end
    end
  end
end
