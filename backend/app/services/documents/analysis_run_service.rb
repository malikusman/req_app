# frozen_string_literal: true

module Documents
  class AnalysisRunService
    RAG_CONFIDENCE = 0.72
    MAX_OPEN_QUESTIONS = 12

    def self.call(run_id:)
      new(run_id: run_id).call
    end

    def initialize(run_id:)
      @run = DocumentAnalysisRun.find(run_id)
      @company = @run.company
    end

    def call
      return if @run.status == "completed"

      @run.update!(status: "running", started_at: Time.current, phase: "lock", error_message: nil)
      emit!("coordinator", "started", "Analysis run started (#{@run.run_kind})")

      docs = resolve_documents!
      @run.update!(document_ids: docs.map(&:id), phase: "ingest")

      texts = {}
      unless @run.run_kind == "profile_reground"
        docs.each do |doc|
          emit!("ingest", "step", "Ingesting #{doc.filename}", document_id: doc.id)
          result = Documents::IngestDocumentService.call(document: doc)
          if result[:ok]
            texts[doc.id] = result[:text].to_s
            skipped = result[:skipped] ? " (unchanged, skipped re-embed)" : ""
            emit!(
              "ingest",
              "step",
              "Ingested #{doc.filename} (#{result[:chunk_count]} chunks)#{skipped}",
              document_id: doc.id
            )
          else
            emit!("ingest", "error", "Failed #{doc.filename}: #{result[:error]}", document_id: doc.id)
          end
        end
      end

      @run.update!(phase: "analyze")
      emit!("coordinator", "step", "Calling docs analysis agents")

      payload = build_langgraph_payload(docs, texts)
      analysis = call_langgraph(payload)
      persist_agent_events!(analysis)

      @run.update!(phase: "persist_kb")
      persist_knowledge!(analysis, docs)
      persist_questions!(analysis)

      @run.update!(phase: "rag")
      Documents::ClarificationRagService.call(company: @company, run: @run)

      finalize!(docs, analysis)
    rescue StandardError => e
      fail_processing_docs!(docs) if defined?(docs) && docs
      @run.update!(
        status: "failed",
        phase: "failed",
        error_message: e.message,
        finished_at: Time.current
      )
      emit!("coordinator", "error", e.message)
      raise
    end

    private

    def resolve_documents!
      case @run.run_kind
      when "profile_reground"
        @company.documents.ready.portal.limit(100).to_a
      when "incremental_docs"
        docs = @company.documents.portal.awaiting_analysis.order(:id).to_a
        if @run.document_ids.present?
          extra = @company.documents.where(id: @run.document_ids).to_a
          docs = (docs + extra).uniq(&:id)
        end
        docs
      else # full
        @company.documents.portal
          .where(status: %w[uploaded failed ready pending])
          .where(purged_at: nil)
          .order(:id).to_a
      end
    end

    def build_langgraph_payload(docs, texts)
      {
        run_id: @run.id,
        run_kind: @run.run_kind,
        company_profile: @run.profile_snapshot.presence || profile_snapshot,
        documents: docs.map do |d|
          chunks = d.document_chunks.order(:chunk_index).limit(12).pluck(:id, :content)
          {
            id: d.id,
            filename: d.filename,
            content_type: d.content_type,
            department: d.department,
            document_type: d.document_type,
            text_excerpt: (texts[d.id] || chunks.map(&:last).join("\n")).to_s.truncate(8000),
            chunk_ids: chunks.map(&:first),
            chunk_previews: chunks.map { |id, c| { id: id, content: c.to_s.truncate(400) } }
          }
        end,
        existing_knowledge: @company.company_knowledge_entries.active.limit(80).map do |e|
          { id: e.id, entry_type: e.entry_type, title: e.title, content: e.content.to_s.truncate(600) }
        end,
        existing_questions: @company.company_clarification_questions
          .where(status: %w[open answered auto_answered dismissed_by_reviewer])
          .limit(40)
          .pluck(:id, :body, :status)
          .map { |id, body, status| { id: id, body: body, status: status } },
        limits: {
          max_questions: MAX_OPEN_QUESTIONS,
          model_fast: ENV.fetch("DOCS_MODEL_FAST", ENV.fetch("OPENAI_MODEL", "gpt-4o-mini")),
          model_reasoning: ENV.fetch("DOCS_MODEL_REASONING", ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"))
        }
      }
    end

    def call_langgraph(payload)
      Langgraph::Client.new.run_docs_analysis!(payload)
    rescue Langgraph::UnavailableError => e
      emit!("coordinator", "warning", "LangGraph unavailable (#{e.message}); using local fallback")
      Documents::LocalDocsAnalysisFallback.call(payload)
    end

    def persist_knowledge!(analysis, docs)
      entries = Array(analysis["knowledge_entries"] || analysis[:knowledge_entries])
      @touched_content_hashes = []

      if @run.run_kind == "full"
        @company.company_knowledge_entries.active.find_each { |e| e.update!(status: "superseded") }
        stale_open_questions!
      end

      entries.each do |raw|
        h = raw.to_h.stringify_keys
        title = h["title"].to_s.strip
        content = h["content"].to_s.strip
        next if title.blank? || content.blank?

        hash = Digest::SHA256.hexdigest("#{title.downcase}|#{content.downcase}")
        @touched_content_hashes << hash
        existing = @company.company_knowledge_entries.active.find_by(content_hash: hash)
        attrs = {
          document_analysis_run: @run,
          entry_type: (h["entry_type"].presence_in(CompanyKnowledgeEntry::ENTRY_TYPES) || "other"),
          title: title.truncate(200),
          content: content,
          confidence: h["confidence"].to_f.clamp(0.0, 1.0).nonzero? || 0.6,
          department: h["department"],
          status: "active",
          content_hash: hash,
          source_document_ids: Array(h["source_document_ids"]).map(&:to_i).uniq,
          source_chunk_ids: Array(h["source_chunk_ids"]).map(&:to_i).uniq,
          metadata: h["metadata"].is_a?(Hash) ? h["metadata"] : {}
        }
        if existing
          existing.update!(attrs)
        else
          @company.company_knowledge_entries.create!(attrs)
        end
      end

      supersede_stale_incremental_entries!(docs) if @run.run_kind == "incremental_docs" && docs.any?

      emit!("knowledge_synthesizer", "step", "Persisted #{entries.size} knowledge entries") unless entries.empty?
    end

    # Drop active KB that still cites re-analyzed docs but was not re-emitted this run.
    def supersede_stale_incremental_entries!(docs)
      doc_ids = docs.map(&:id)
      touched = @touched_content_hashes || []
      @company.company_knowledge_entries.active.find_each do |entry|
        sources = Array(entry.source_document_ids).map(&:to_i)
        next if sources.intersection(doc_ids).empty?
        next if touched.include?(entry.content_hash)
        next if entry.document_analysis_run_id == @run.id

        entry.update!(status: "superseded")
      end
    end

    def persist_questions!(analysis)
      questions = Array(analysis["questions"] || analysis[:questions])
      return if questions.empty?

      existing_bodies = @company.company_clarification_questions
        .where(status: %w[open answered auto_answered dismissed_by_reviewer])
        .pluck(:body)
        .map { |b| normalize_q(b) }

      created = 0
      questions.first(MAX_OPEN_QUESTIONS).each do |raw|
        h = raw.to_h.stringify_keys
        body = h["body"].to_s.strip
        next if body.blank?
        next if existing_bodies.include?(normalize_q(body))

        @company.company_clarification_questions.create!(
          document_analysis_run: @run,
          body: body,
          status: "pending_rag",
          metadata: { "rationale" => h["rationale"] }.compact
        )
        created += 1
      end
      emit!("question_generator", "step", "Created #{created} draft questions")
    end

    def finalize!(docs, analysis)
      failed = 0
      summaries = Array(analysis["document_summaries"] || analysis[:document_summaries])
      knowledge = Array(analysis["knowledge_entries"] || analysis[:knowledge_entries])

      docs.each do |doc|
        doc.reload
        if doc.status == "failed"
          failed += 1
        elsif doc.status.in?(%w[processing uploaded pending]) || doc.document_chunks.exists?
          preview = enrich_insights_preview(doc, analysis, summaries, knowledge)
          doc.update!(status: "ready", insights_preview: preview, processing_error: nil)
        end
      end

      @company.update!(docs_profile_stale_at: nil) if @run.run_kind == "profile_reground"

      status = failed.positive? ? "completed_with_errors" : "completed"
      @run.update!(
        status: status,
        phase: "done",
        finished_at: Time.current,
        summary: {
          "knowledge_count" => @company.company_knowledge_entries.active.count,
          "open_questions" => @company.company_clarification_questions.open_for_admin.count,
          "agent_summary" => analysis["summary"] || analysis[:summary],
          "intelligence_queued" => true
        },
        counters: {
          "documents" => docs.size,
          "failed_documents" => failed,
          "events" => @run.document_analysis_events.count
        }
      )
      emit!("run_reporter", "completed", "Run #{status}")
      # Company-scoped so docs-first readiness/signals refresh and stale signals can be pruned.
      AggregateIntelligenceJob.perform_later(@company.id)
      emit!("coordinator", "step", "Queued intelligence refresh")
    end

    def enrich_insights_preview(doc, analysis, summaries, knowledge)
      summary =
        summaries.find { |s| s.to_h.stringify_keys["document_id"].to_i == doc.id }&.then { |s| s.to_h.stringify_keys["summary"] } ||
        (doc.insights_preview.is_a?(Hash) ? doc.insights_preview["summary"] : nil) ||
        (analysis["summary"] || analysis[:summary]).presence ||
        "Analyzed in run ##{@run.id}"

      related = knowledge.filter_map do |raw|
        h = raw.to_h.stringify_keys
        ids = Array(h["source_document_ids"]).map(&:to_i)
        next unless ids.empty? || ids.include?(doc.id)

        h
      end

      systems = related.select { |h| h["entry_type"].to_s.in?(%w[system tool]) }.map { |h| h["title"].to_s }.compact_blank.uniq
      friction = related.select { |h| h["entry_type"].to_s.in?(%w[risk process]) }.map { |h| h["title"].to_s }.compact_blank.uniq
      workflows = related.select { |h| h["entry_type"].to_s == "process" }.map { |h| h["title"].to_s }.compact_blank.uniq

      (doc.insights_preview.is_a?(Hash) ? doc.insights_preview : {}).merge(
        "summary" => summary.to_s.truncate(800),
        "tools_mentioned" => systems.first(12),
        "systems" => systems.first(12),
        "friction_points" => friction.first(12),
        "workflows" => workflows.first(12),
        "analysis_run_id" => @run.id
      )
    end

    def stale_open_questions!
      @company.company_clarification_questions
        .where(status: %w[open pending_rag])
        .update_all(status: "stale", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def profile_snapshot
      Companies::AgentContext.docs_profile_snapshot(@company)
    end

    def emit!(agent, event_type, message, **payload)
      @run.document_analysis_events.create!(
        agent_name: agent,
        event_type: event_type,
        phase: @run.phase,
        message: message,
        payload: payload
      )
    end

    def persist_agent_events!(analysis)
      Array(analysis["events"] || analysis[:events]).each do |raw|
        h = raw.to_h.stringify_keys
        agent = h["agent_name"].presence || h["agent"].presence || "agent"
        emit!(
          agent,
          h["event_type"].presence || "step",
          h["message"].to_s.presence || agent.to_s,
          **h.except("agent_name", "agent", "event_type", "message").symbolize_keys
        )
      end
    end

    def fail_processing_docs!(docs)
      Array(docs).each do |doc|
        doc.reload
        next unless doc.status == "processing"

        doc.update!(status: "failed", processing_error: "Analysis run failed")
      end
    rescue StandardError
      nil
    end

    def normalize_q(body)
      body.to_s.downcase.gsub(/\s+/, " ").strip
    end
  end
end
