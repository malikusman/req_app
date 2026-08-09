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
      document_sources = gather_document_sources
      derived_texts = gather_derived_texts
      message_sources = gather_message_sources
      multimodal = gather_multimodal_sources
      return [] if document_sources.blank? && derived_texts.blank? && multimodal.blank? && message_sources.blank?

      detected = []
      RULES.each do |rule|
        docs_matched = document_sources.count { |d| d[:blobs].any? { |b| b.match?(rule[:pattern]) } }
        derived_hits = derived_texts.count { |t| t.match?(rule[:pattern]) }
        source_excerpts = message_evidence_for(rule, message_sources) # distinct messages, capped
        evidence = multimodal_evidence_for(rule, multimodal)

        # Believable, de-duplicated primary evidence: distinct documents +
        # distinct interview messages + media attachments. Derived text (facts,
        # knowledge, insight summaries) only corroborates — it is not counted as
        # a "piece of evidence" (that produced the old inflated "163 evidence").
        evidence_count = docs_matched + source_excerpts.size + evidence.size
        next if evidence_count.zero? && derived_hits.zero?

        # Saturating absolute-evidence curve so strong signals actually reach
        # "High" (the old hits/whole-corpus ratio jammed everything to ~0.35–0.45).
        weighted = evidence_count + 0.3 * derived_hits
        strength = (1.0 - Math.exp(-weighted / 6.0)).round(2)
        strength = 0.2 if strength < 0.2 && weighted.positive?

        detected << {
          label: rule[:label],
          signal_type: rule[:type],
          strength: strength,
          evidence_count: [evidence_count, 1].max,
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

    # Corroborating (non-primary) text: insight summaries, memory facts and
    # knowledge entries. Documents and interview messages are counted separately
    # as distinct primary evidence, so they are deliberately excluded here to
    # avoid the double-count that inflated evidence and starved strength.
    def gather_derived_texts
      insight_texts = ConversationInsight.where(company_id: @company.id).pluck(:summary)
      fact_texts = @company.company_memory_facts.limit(200).pluck(:content)
      knowledge_texts = gather_knowledge_texts
      (insight_texts + fact_texts + knowledge_texts).compact_blank
    end

    # One entry per ready document, each carrying its text blobs, so a rule can
    # match a document once (distinct-document evidence) rather than once per chunk.
    def gather_document_sources
      @company.documents.where(status: "ready").filter_map do |document|
        blobs = document_text_blobs(document)
        next if blobs.blank?

        { document_id: document.id, blobs: blobs }
      end
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

    NEGATION_PATTERN = /\b(no|not|never|none|isn'?t|aren'?t|don'?t|doesn'?t|didn'?t|without|hardly|rarely)\b/i
    SELF_INTRO_PATTERN = /\A\s*(hi|hello|hey|my name is|i am|i'?m|thanks|thank you)\b/i

    # Rank matching interview messages by how well the *matched sentence* speaks
    # to the signal — dropping negations ("there are no manual steps") and
    # self-intros so the pull-quote actually supports the finding, not refutes it.
    def message_evidence_for(rule, message_sources)
      message_sources.filter_map do |source|
        sentence = best_sentence_for(source[:body], rule[:pattern])
        next unless sentence
        next if sentence.match?(SELF_INTRO_PATTERN)
        next if negated_match?(sentence, rule[:pattern])

        score = relevance_score(sentence, rule[:pattern])
        next if score.zero?

        {
          message_id: source[:message_id],
          employee_id: source[:employee_id],
          conversation_id: source[:conversation_id],
          excerpt: sentence.truncate(200),
          score: score
        }
      end.sort_by { |e| -e[:score] }.first(MAX_EVIDENCE).map { |e| e.except(:score) }
    end

    # Pick the sentence within the message that actually contains the match, so
    # relevance/negation are judged locally instead of across the whole message.
    def best_sentence_for(body, pattern)
      sentences = body.to_s.split(/(?<=[.!?])\s+/)
      sentences.find { |s| s.match?(pattern) } || (body.to_s.match?(pattern) ? body.to_s : nil)
    end

    # True when a negation token sits close before the matched term (within ~40
    # chars), i.e. the statement denies the signal rather than evidencing it.
    def negated_match?(sentence, pattern)
      md = sentence.match(pattern)
      return false unless md

      window = sentence[[md.begin(0) - 40, 0].max...md.begin(0)].to_s
      window.match?(NEGATION_PATTERN)
    end

    def relevance_score(sentence, pattern)
      hits = sentence.scan(pattern).size
      # Prefer substantive but not rambling sentences; penalise extremes.
      length_ok = sentence.length.between?(30, 400) ? 1 : 0
      hits + length_ok
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
        # Topic-only inference is a single weak mention — keep it honestly Low so
        # it never outranks a signal backed by documents, interviews or media.
        { label: rule[:label], signal_type: rule[:type], strength: 0.3, evidence_count: 1, multimodal_evidence: [], source_excerpts: [] }
      end
    end
  end
end
