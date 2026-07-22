# frozen_string_literal: true

module Catalog
  class CompanyFitService
    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      stack_names = if defined?(CompanySystem) && CompanySystem.table_exists?
                      @company.company_systems.active.pluck(:name, :normalized_name)
                    else
                      []
                    end
      stack_normalized = stack_names.map { |(_name, norm)| norm }

      matches = []
      @company.company_signals.order(strength: :desc).limit(20).each do |signal|
        Intelligence::CatalogMatcher.call(signal: signal).each do |match|
          entry = SolutionCatalogEntry.find_by(id: match[:solution_id])
          next unless entry

          already_in_stack = stack_intersects?(entry, stack_normalized)
          score = adjust_score(match[:score] || 0, entry: entry)
          prose = fit_prose(entry: entry, signal: signal, already_in_stack: already_in_stack, match: match)

          record = CompanyCatalogMatch.find_or_initialize_by(
            company: @company,
            solution_catalog_entry_id: entry.id
          )
          record.assign_attributes(
            score: score,
            why_it_fits: prose,
            evidence_used: [
              { "signal_id" => signal.id, "label" => signal.label },
              { "already_in_stack" => already_in_stack },
              { "stack" => stack_names.map(&:first).first(8) },
              { "industry" => @company.profile_value("industry") },
              { "size_band" => @company.profile_value("size_band") }
            ].compact,
            assumptions: already_in_stack ? ["Capability may extend an existing system rather than replace it"] : [],
            risks: ["Catalog suggestion is advisory until reviewer endorsement"],
            estimated_effort: already_in_stack ? "low" : effort_for_size,
            validate_next: already_in_stack ?
              "Validate how this extends the systems already in use" :
              "Confirm systems and security constraints with stakeholders",
            catalog_version: entry.updated_at.iso8601,
            matched_at: Time.current
          )
          record.save!
          matches << record
        end
      end
      matches
    end

    private

    def stack_intersects?(entry, stack_normalized)
      needles = [
        entry.name,
        entry.vendor,
        *Array(entry.try(:required_systems)),
        *Array(entry.try(:match_keywords)),
        *Array(entry.try(:tags))
      ].map { |v| CompanySystem.normalize(v) }.reject(&:blank?)

      needles.any? { |n| stack_normalized.any? { |s| s.include?(n) || n.include?(s) } }
    end

    def adjust_score(base, entry:)
      score = base.to_f
      industry = @company.profile_value("industry").to_s.downcase
      if industry.present?
        entry_industries = Array(entry.try(:industries)).map { |i| i.to_s.downcase }
        score += 0.12 if entry_industries.any? { |i| i.include?(industry) || industry.include?(i) }
        score -= 0.05 if entry_industries.any? && entry_industries.none? { |i| i.include?(industry) || industry.include?(i) }
      end

      size = @company.profile_value("size_band").to_s
      # Prefer lighter tools for small orgs, broader platforms for larger ones.
      if size.in?(%w[1-10 11-50]) && entry.name.to_s.match?(/enterprise|suite/i)
        score -= 0.04
      elsif size.in?(%w[201-1000 1000+]) && entry.name.to_s.match?(/starter|smb|small/i)
        score -= 0.03
      elsif size.present?
        score += 0.02
      end

      score.clamp(0.0, 1.0).round(4)
    end

    def effort_for_size
      size = @company.profile_value("size_band").to_s
      return "high" if size.in?(%w[201-1000 1000+])
      return "low" if size.in?(%w[1-10 11-50])

      "medium"
    end

    def fit_prose(entry:, signal:, already_in_stack:, match:)
      required = Array(entry.try(:required_systems)).presence
      caps = Array(entry.try(:capabilities)).first(3)
      industry = @company.profile_value("industry")
      size = @company.profile_value("size_band")
      parts = []
      parts << if already_in_stack
                 "#{entry.name} appears adjacent to systems already in #{@company.display_name || @company.name}'s stack, so rollout can extend existing tooling rather than introduce a greenfield platform."
               else
                 "#{entry.name} is a candidate capability for the friction around \"#{signal.label}\"."
               end
      if industry.present? || size.present?
        framing = [industry.presence, size.present? ? "size #{size}" : nil].compact.join(", ")
        parts << "Company context: #{framing}."
      end
      parts << "It aligns with required systems (#{required.join(', ')})." if required
      parts << "Relevant capabilities: #{caps.join(', ')}." if caps.any?
      reason = match[:reason].to_s
      parts << "Match basis: #{reason.truncate(100)}." if reason.present?
      parts.join(" ")
    end
  end
end
