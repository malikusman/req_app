# frozen_string_literal: true

module Knowledge
  class IndexProfileService
    SECTION_SOURCE_IDS = {
      "basics" => 1,
      "strategy" => 2,
      "operations" => 3,
      "technology_data" => 4,
      "people_culture" => 5,
      "gaps_constraints" => 6,
      "documents_ack" => 7
    }.freeze

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
      @context = (company.profile_context || {}).deep_stringify_keys
    end

    def call
      indexed = []
      SECTION_SOURCE_IDS.each do |section, source_id|
        chunk = index_section!(section, source_id)
        indexed << chunk if chunk
      end

      index_full_profile!
      indexed
    end

    private

    def index_section!(section, source_id)
      data = @context[section]
      return if data.blank?

      content = format_section(section, data)
      return if content.blank?

      embedding = Openai::Client.new.embedding(content)
      chunk = KnowledgeChunk.find_or_initialize_by(
        company_id: @company.id,
        source_type: "profile_section",
        source_id: source_id
      )
      chunk.assign_attributes(
        content: content.truncate(4000),
        embedding: embedding,
        embedding_model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        embedded_at: Time.current,
        metadata: { title: section_label(section), section: section }
      )
      chunk.save!
      chunk
    end

    def index_full_profile!
      summary = Companies::ProfileSummary.for_ai(company: @company)
      return if summary.blank?

      embedding = Openai::Client.new.embedding(summary)
      chunk = KnowledgeChunk.find_or_initialize_by(
        company_id: @company.id,
        source_type: "profile_section",
        source_id: @company.id
      )
      chunk.assign_attributes(
        content: summary.truncate(8000),
        embedding: embedding,
        embedding_model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        embedded_at: Time.current,
        metadata: { title: "Company profile (full)" }
      )
      chunk.save!
      chunk
    end

    def format_section(section, data)
      lines = ["#{section_label(section)}:"]
      data.each do |key, value|
        formatted = case value
                    when Array then value.join(", ")
                    else value.to_s
                    end
        lines << "  #{key.humanize}: #{formatted}" if formatted.strip.present?
      end
      lines.join("\n")
    end

    def section_label(section)
      {
        "basics" => "Company basics",
        "strategy" => "Strategy and goals",
        "operations" => "Operations and systems",
        "technology_data" => "Technology and data",
        "people_culture" => "People and culture",
        "gaps_constraints" => "Gaps and constraints",
        "documents_ack" => "Documents acknowledgment"
      }[section] || section.humanize
    end
  end
end
