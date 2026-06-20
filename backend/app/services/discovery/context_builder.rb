# frozen_string_literal: true

module Discovery
  # Assembles the multi-agent turn context: limits, profile, blackboard, and
  # (flag-gated) memory retrieval — top-k similar company facts and document
  # chunks for cross-employee recall.
  class ContextBuilder
    FACT_LIMIT = 3
    CHUNK_LIMIT = 2

    def self.limits_for(company)
      settings = company.merged_settings
      {
        max_followup_depth: settings.fetch("discovery_max_followup_depth", 2).to_i,
        max_questions_per_agent: settings.fetch("discovery_max_questions_per_agent", 5).to_i,
        max_active_agents: settings.fetch("discovery_max_active_agents", 4).to_i
      }
    end

    def self.call(conversation:, employee:, user_message:)
      new(conversation: conversation, employee: employee, user_message: user_message).call
    end

    def initialize(conversation:, employee:, user_message:)
      @conversation = conversation
      @employee = employee
      @company = employee.company
      @user_message = user_message
    end

    def call
      {
        profile: profile,
        blackboard: blackboard,
        limits: self.class.limits_for(@company),
        memory_facts: memory_facts,
        document_snippets: document_snippets
      }
    end

    private

    def profile
      @conversation.blackboard["profile"] || @employee.profile_card
    end

    def blackboard
      bb = @conversation.blackboard
      bb.presence
    end

    def retrieval_enabled?
      @company.merged_settings["discovery_memory_retrieval_enabled"] == true &&
        ENV["OPENAI_API_KEY"].present?
    end

    def query_embedding
      return @query_embedding if defined?(@query_embedding)

      @query_embedding = Openai::Client.new.embedding(@user_message.to_s.truncate(1000))
    rescue StandardError => e
      Rails.logger.warn("[ContextBuilder] embedding failed: #{e.message}")
      @query_embedding = nil
    end

    def memory_facts
      return [] unless retrieval_enabled?
      return [] if query_embedding.blank?

      scope = @company.company_memory_facts.embedded
      scope = scope.where.not(employee_id: @employee.id) if @employee.id
      scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine")
           .first(FACT_LIMIT)
           .map { |fact| { content: fact.content, fact_type: fact.fact_type, department: fact.department } }
    rescue StandardError => e
      Rails.logger.warn("[ContextBuilder] fact retrieval failed: #{e.message}")
      []
    end

    def document_snippets
      return [] unless retrieval_enabled?
      return [] if query_embedding.blank?

      snippets = conversation_document_snippets
      remaining = CHUNK_LIMIT - snippets.size
      snippets += company_document_snippets(limit: remaining) if remaining.positive?
      snippets.uniq
    rescue StandardError => e
      Rails.logger.warn("[ContextBuilder] chunk retrieval failed: #{e.message}")
      []
    end

    def conversation_document_snippets
      scope = document_chunk_scope.where(documents: { conversation_id: @conversation.id })
      nearest_chunks(scope, 1).map(&:content)
    end

    def company_document_snippets(limit:)
      scope = document_chunk_scope
      scope = scope.where.not(documents: { conversation_id: @conversation.id }) if @conversation.id
      nearest_chunks(scope, limit).map(&:content)
    end

    def document_chunk_scope
      DocumentChunk.joins(:document).where(documents: { company_id: @company.id, status: "ready" })
    end

    def nearest_chunks(scope, limit)
      return [] if limit <= 0

      scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(limit)
    end
  end
end
