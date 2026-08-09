# frozen_string_literal: true

module Companion
  # Company catalog / matches first; optional labeled general suggestions second.
  class ToolsSuggestService
    MAX_COMPANY = 3

    def self.call(employee:, query:)
      new(employee: employee, query: query).call
    end

    def initialize(employee:, query:)
      @employee = employee
      @company = employee.company
      @query = query.to_s.strip
    end

    def call
      company_hits = company_suggestions
      general = []
      if company_hits.size < 2
        general = general_suggestions(exclude_names: company_hits.map { |h| h[:name] })
      end

      {
        company: company_hits,
        general: general,
        assistant_message: format_message(company_hits, general)
      }
    end

    private

    def company_suggestions
      tags = [@employee.department, @employee.role_title].compact
      matched = Catalog::HybridMatcher.call(
        query: @query.presence || tags.join(" "),
        tags: tags,
        keywords: tags,
        limit: MAX_COMPANY
      )

      curated = CompanyCatalogMatch.where(company_id: @company.id)
                                   .includes(:solution_catalog_entry)
                                   .order(score: :desc)
                                   .limit(MAX_COMPANY)
                                   .filter_map do |m|
                                     entry = m.solution_catalog_entry
                                     next unless entry

                                     {
                                       name: entry.name,
                                       vendor: entry.vendor,
                                       reason: "Matched for #{@company.display_name || @company.name}",
                                       source: "company_catalog"
                                     }
                                   end

      recs = @company.recommendations.published.limit(MAX_COMPANY).filter_map do |r|
        title = r.title.to_s
        next if title.blank?

        {
          name: title,
          vendor: nil,
          reason: r.description.to_s.truncate(120).presence || "From your company recommendations",
          source: "recommendation"
        }
      end

      merged = []
      seen = {}
      (matched.map { |m| hybrid_hit(m) } + curated + recs).each do |hit|
        key = hit[:name].to_s.downcase
        next if key.blank? || seen[key]

        seen[key] = true
        merged << hit
        break if merged.size >= MAX_COMPANY
      end
      merged
    end

    def hybrid_hit(m)
      {
        name: m[:name] || m["name"],
        vendor: m[:vendor] || m["vendor"],
        reason: (m[:reason] || m["reason"]).to_s.truncate(120),
        source: "catalog"
      }
    end

    def general_suggestions(exclude_names:)
      return [] unless Openai::Client.new.configured? || MocksAllowed.allowed?

      result = Openai::Client.new.companion_general_tools(
        query: @query,
        department: @employee.department,
        job_title: @employee.role_title,
        exclude_names: exclude_names
      )
      Array(result["suggestions"]).first(2).filter_map do |s|
        name = s.is_a?(Hash) ? s["name"].to_s : s.to_s
        next if name.blank?

        {
          name: name,
          vendor: s.is_a?(Hash) ? s["vendor"] : nil,
          reason: s.is_a?(Hash) ? s["why"].to_s.truncate(120) : "General suggestion",
          source: "general"
        }
      end
    rescue StandardError => e
      Rails.logger.warn("[Companion::ToolsSuggest] general failed: #{e.class}: #{e.message}")
      []
    end

    def format_message(company_hits, general)
      parts = []
      if company_hits.any?
        parts << "From your company catalog / matches:"
        company_hits.each_with_index do |h, i|
          line = "#{i + 1}. #{h[:name]}"
          line += " (#{h[:vendor]})" if h[:vendor].present?
          line += " — #{h[:reason]}" if h[:reason].present?
          parts << line
        end
      else
        parts << "I don't have a strong company-catalog match for that yet."
      end

      if general.any?
        parts << ""
        parts << "Not from your company catalog (general ideas only):"
        general.each_with_index do |h, i|
          line = "#{i + 1}. #{h[:name]}"
          line += " — #{h[:reason]}" if h[:reason].present?
          parts << line
        end
      end

      parts << ""
      parts << "Want something added to your discovery interview for the company report? Say \"add this to my interview\"."
      parts.join("\n")
    end
  end
end
