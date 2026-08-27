# frozen_string_literal: true

module Discovery
  # Assembles the interview turn context: limits, profile, blackboard, and
  # (flag-gated) memory retrieval — top-k similar company facts and document
  # chunks for cross-employee recall.
  class ContextBuilder
    FACT_LIMIT = 3
    CHUNK_LIMIT = 2
    # Cosine distance from neighbor gem; keep only reasonably similar memories.
    MAX_COSINE_DISTANCE = 0.35

    # Interview limits, resolved company setting -> ENV -> code default.
    #
    # These keys are deliberately absent from Company::DEFAULT_SETTINGS. merged_settings
    # merges the defaults in, so a key present there would always be "set" and ENV
    # could never win. Their absence is what makes the precedence work: the key
    # appears only when an operator set it for that company.
    LIMIT_DEFAULTS = {
      # A BACKSTOP, not a target. The interview closes on a filled dossier, usually
      # several questions earlier. If this fires often, the dossier wants too much.
      "discovery_max_questions" => { env: "DISCOVERY_MAX_QUESTIONS", default: 8, cast: :int },
      # Without a floor, a two-word-answer employee trips the stall exit at turn 3
      # and the discovery package gets built on almost nothing.
      "discovery_min_questions" => { env: "DISCOVERY_MIN_QUESTIONS", default: 4, cast: :int },
      "discovery_stall_turns" => { env: "DISCOVERY_STALL_TURNS", default: 2, cast: :int },
      "discovery_slot_confidence" => { env: "DISCOVERY_SLOT_CONFIDENCE", default: 0.6, cast: :float },
      "discovery_orient_questions" => { env: "DISCOVERY_ORIENT_QUESTIONS", default: 3, cast: :int },
      "discovery_switch_after" => { env: "DISCOVERY_SWITCH_AFTER", default: 3, cast: :int }
    }.freeze

    # The agent-side keys are short (max_questions, not discovery_max_questions).
    AGENT_KEY = ->(setting_key) { setting_key.delete_prefix("discovery_").to_sym }

    def self.limits_for(company)
      # Read the raw column, NOT merged_settings: merged_settings folds
      # DEFAULT_SETTINGS in, which would make every key look operator-set.
      overrides = company.settings.is_a?(Hash) ? company.settings : {}

      LIMIT_DEFAULTS.each_with_object({}) do |(key, spec), out|
        out[AGENT_KEY.call(key)] = resolve_limit(overrides[key], spec)
      end
    end

    def self.resolve_limit(override, spec)
      raw = override.presence || ENV[spec[:env]].presence
      return spec[:default] if raw.nil?

      spec[:cast] == :float ? raw.to_f : raw.to_i
    end
    private_class_method :resolve_limit

    def self.call(conversation:, employee:, user_message:, inbound_message: nil)
      new(conversation: conversation, employee: employee, user_message: user_message,
          inbound_message: inbound_message).call
    end

    def initialize(conversation:, employee:, user_message:, inbound_message: nil)
      @conversation = conversation
      @employee = employee
      @company = employee.company
      @user_message = user_message
      @inbound_message = inbound_message
    end

    def call
      {
        profile: profile,
        blackboard: blackboard,
        limits: self.class.limits_for(@company),
        memory_facts: memory_facts,
        document_snippets: document_snippets,
        knowledge_snippets: knowledge_snippets,
        media_context: media_context,
        media_snippets: media_snippets,
        company_profile: Companies::AgentContext.for_agents(@company)
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
           .select { |fact| relevant_neighbor?(fact) }
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

    def knowledge_snippets
      @company.company_knowledge_entries.active.order(updated_at: :desc).limit(5).map do |e|
        "#{e.entry_type}: #{e.title} — #{e.content.to_s.truncate(300)}"
      end
    rescue StandardError => e
      Rails.logger.warn("[ContextBuilder] knowledge retrieval failed: #{e.message}")
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

      scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine")
           .first(limit)
           .select { |chunk| relevant_neighbor?(chunk) }
    end

    def relevant_neighbor?(record)
      distance = record.try(:neighbor_distance)
      return true if distance.nil?

      distance.to_f <= MAX_COSINE_DISTANCE
    end

    def media_context
      return nil unless @inbound_message

      attachment = @inbound_message.media_attachment
      return nil unless attachment&.status == "ready"

      insights = attachment.structured_insights.presence || {}
      safe_insights = insights.except("raw_excerpt")

      {
        type: attachment.attachment_type,
        caption: attachment.caption,
        summary: attachment.extracted_text.to_s.truncate(500),
        confidence: attachment.confidence,
        insights: safe_insights.presence
      }.compact
    end

    def media_snippets
      return [] unless retrieval_enabled?
      return [] if query_embedding.blank?

      scope = document_chunk_scope.where(
        documents: { conversation_id: @conversation.id, source: "whatsapp_upload" }
      )
      nearest_chunks(scope, CHUNK_LIMIT).map(&:content)
    rescue StandardError => e
      Rails.logger.warn("[ContextBuilder] media snippet retrieval failed: #{e.message}")
      []
    end
  end
end
