# frozen_string_literal: true

module Synthesis
  # Stage C: P10 judges each shortlisted pair (Doc 10 §8, P10). One call per
  # pair, in the background, with only what the pair needs — the two items, the
  # employees' own words about them, the signals that shortlisted them, the
  # company's departments and systems, and the cluster one of them is already in.
  # Never names, never transcripts, never anything from leadership (P10 §3).
  #
  # When P10 can't be used — switched off, no model, an error, a reply that
  # won't parse or validate twice — the pair is kept separate and queued for the
  # consultant (P10 §8). Under-merging shows as two similar findings someone can
  # group; over-merging hides work nobody notices is missing.
  class RelationshipClassifier
    CONTEXT_CLASSES = %w[OTHER_EMPLOYEE_PRIVATE].freeze

    def self.call(run:, pairs:, client: Synthesis.client_for(run.company), existing_clusters: {})
      new(run, pairs, client, existing_clusters).call
    end

    # existing_clusters: { item id => cluster name } for items already grouped.
    def initialize(run, pairs, client, existing_clusters)
      @run = run
      @pairs = pairs
      @client = client
      @existing = existing_clusters
      @company_context = company_context
      @drops = []
    end

    attr_reader :drops

    def call
      @pairs.map { |pair| classify(pair) }
    end

    private

    def classify(pair)
      log = RunLog.new(run: @run, stage: "P10", prompt_version: Openai::Client::PROCESS_RELATIONSHIP_PROMPT_VERSION,
                       context_classes: CONTEXT_CLASSES)
      verdict, reason = from_model(pair, log)
      if verdict
        log.record!(status: log.calls > 1 ? "RETRIED" : "OK")
        store(pair, verdict, origin: "AI")
      else
        log.record!(status: "FALLBACK", fallback_reason: reason)
        store(pair, fallback(reason), origin: "FALLBACK")
      end
    end

    def from_model(pair, log)
      return [nil, "model_off"] unless Llm::Synthesis.enabled? && @client.configured?
      return [nil, "model_unavailable"] if OpenaiCircuitBreaker.open?

      2.times do
        result = @client.process_relationship(system: Synthesis.system_prompt("p10_process_relationship.v1.txt"),
                                              context: context(pair))
        log.add(result)
        validator = RelationshipValidator.new(@client.parse_reply(result.content))
        verdict = validator.call
        validator.corrections.each { |c| @drops << { "stage" => "P10", "pair" => [pair.a.id, pair.b.id], "note" => c } }
        return [verdict, nil]
      rescue JSON::ParserError, RelationshipValidator::Invalid => e
        @drops << { "stage" => "P10", "pair" => [pair.a.id, pair.b.id], "note" => "unusable reply: #{e.message}" }
        next
      end
      [nil, "unusable_reply"]
    rescue Openai::Client::Error, Timeout::Error, SystemCallError, IOError => e
      Rails.logger.warn("[Synthesis::RelationshipClassifier] run=#{@run.id} #{e.class}: #{e.message}")
      [nil, "model_error"]
    end

    def fallback(reason)
      {
        "relationship_type" => "INDEPENDENT", "confidence" => "LOW", "recommendation" => "KEEP_SEPARATE",
        "same_execution" => "UNKNOWN", "tests" => {}, "variant_assessment" => {}, "evidence_for" => [],
        "evidence_against" => [], "effort_note" => nil, "clarification" => nil,
        "rationale" => "Not classified (#{reason.tr('_', ' ')}); kept separate until a consultant decides."
      }
    end

    # The newest verdict on these two findings supersedes any earlier one, so
    # each pair has one current relationship.
    def store(pair, verdict, origin:)
      ProcessRelationship.transaction do
        previous = ProcessRelationship.current.where(engagement_id: @run.engagement_id,
                                                     from_finding_id: pair.a.id, to_finding_id: pair.b.id)
                                      .order(:version).last
        previous&.update!(status: "SUPERSEDED")
        ProcessRelationship.create!(
          verdict.merge(
            company_id: @run.company_id, engagement_id: @run.engagement_id, synthesis_run: @run,
            from_finding_id: pair.a.id, to_finding_id: pair.b.id, pair_digest: pair.digest,
            version: (previous&.version || 0) + 1, parent_version_id: previous&.id, status: "CURRENT",
            origin: origin, prompt_version: origin == "AI" ? Openai::Client::PROCESS_RELATIONSHIP_PROMPT_VERSION : nil,
            schema_version: ProcessRelationship::SCHEMA_VERSION
          )
        )
      end
    end

    # P10 §6, in its order. Item fields are the platform's; what the employee
    # said is labelled as theirs.
    def context(pair)
      [
        %(<company_context trust="platform">\n#{JSON.pretty_generate(@company_context)}\n</company_context>),
        %(<item_a trust="platform">\n#{JSON.pretty_generate(item_fields(pair.a))}\n</item_a>),
        %(<evidence_a trust="participant">\n#{excerpt(pair.a)}\n</evidence_a>),
        %(<item_b trust="platform">\n#{JSON.pretty_generate(item_fields(pair.b))}\n</item_b>),
        %(<evidence_b trust="participant">\n#{excerpt(pair.b)}\n</evidence_b>),
        %(<shared_signals trust="platform">\n#{pair.signals.map { |s| "- #{s}" }.join("\n")}\n</shared_signals>),
        %(<existing_cluster trust="platform">#{@existing[pair.b.id] || @existing[pair.a.id] || 'none'}</existing_cluster>),
        "Classify the relationship."
      ].join("\n\n")
    end

    def item_fields(item)
      { "role" => item.role, "department" => item.department, "title" => item.title, "systems" => item.systems,
        "how_often" => item.frequency, "how_long" => item.duration, "effort_type" => item.effort_type }.compact
    end

    def excerpt(item)
      { "What happens now" => item.wording, "What snags" => item.friction }
        .filter_map { |label, words| "#{label}: #{words}" if words.present? }.join("\n")
    end

    def company_context
      company = @run.company
      profile = company.company_profile || {}
      {
        "industry" => profile["industry"], "business_model" => profile["business_model"],
        "departments" => Array(profile["org_departments"]),
        "systems" => company.company_systems.active.order(:name).limit(30).pluck(:name)
      }.compact
    end
  end
end
