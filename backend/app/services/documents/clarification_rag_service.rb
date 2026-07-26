# frozen_string_literal: true

module Documents
  class ClarificationRagService
    CONFIDENCE = AnalysisRunService::RAG_CONFIDENCE

    def self.call(company:, run:)
      new(company: company, run: run).call
    end

    def initialize(company:, run:)
      @company = company
      @run = run
      @openai = Openai::Client.new
    end

    def call
      questions = @company.company_clarification_questions.where(status: %w[pending_rag open])
      questions.find_each do |q|
        answer_question!(q)
      end
    end

    private

    def answer_question!(question)
      embedding = @openai.embedding(question.body)
      neighbors = DocumentChunk
        .joins(:document)
        .where(documents: { company_id: @company.id, status: "ready" })
        .nearest_neighbors(:embedding, embedding, distance: "cosine")
        .limit(5)
        .to_a

      kb_hits = @company.company_knowledge_entries.active.limit(20).select do |e|
        e.content.to_s.downcase.include?(question.body.to_s.downcase.split(/\s+/).first(3).join(" ")) ||
          similar_enough?(e.title, question.body)
      end.first(3)

      if neighbors.empty? && kb_hits.empty?
        question.update!(status: "open")
        return
      end

      context = neighbors.map(&:content).join("\n---\n")
      kb_context = kb_hits.map { |e| "#{e.title}: #{e.content}" }.join("\n")
      combined = [context, kb_context].reject(&:blank?).join("\n\n")

      result = @openai.answer_from_context(question: question.body, context: combined.to_s.truncate(6000))
      confidence = result["confidence"].to_f
      answer = result["answer"].to_s.strip

      if confidence >= CONFIDENCE && answer.present? && result["grounded"] != false
        question.update!(
          status: "auto_answered",
          answer: answer,
          answer_source: "rag",
          answered_at: Time.current,
          citations: neighbors.map { |c| { "chunk_id" => c.id, "document_id" => c.document_id, "excerpt" => c.content.to_s.truncate(200) } } +
                     kb_hits.map { |e| { "knowledge_entry_id" => e.id, "title" => e.title } }
        )
        @run.document_analysis_events.create!(
          agent_name: "rag_answerer",
          event_type: "step",
          phase: "rag",
          message: "Auto-answered: #{question.body.truncate(80)}",
          payload: { "question_id" => question.id, "confidence" => confidence }
        )
      else
        question.update!(status: "open")
      end
    rescue StandardError => e
      question.update!(status: "open", metadata: question.metadata.merge("rag_error" => e.message))
    end

    def similar_enough?(a, b)
      left = a.to_s.downcase.split(/\W+/).reject { |w| w.length < 4 }
      right = b.to_s.downcase.split(/\W+/).reject { |w| w.length < 4 }
      (left & right).any?
    end
  end
end
