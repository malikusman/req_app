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
          prose = fit_prose(entry: entry, signal: signal, already_in_stack: already_in_stack, match: match)

          record = CompanyCatalogMatch.find_or_initialize_by(
            company: @company,
            solution_catalog_entry_id: entry.id
          )
          record.assign_attributes(
            score: match[:score] || 0,
            why_it_fits: prose,
            evidence_used: [
              { "signal_id" => signal.id, "label" => signal.label },
              { "already_in_stack" => already_in_stack },
              { "stack" => stack_names.map(&:first).first(8) }
            ],
            assumptions: already_in_stack ? ["Capability may extend an existing system rather than replace it"] : [],
            risks: ["Catalog suggestion is advisory until reviewer endorsement"],
            estimated_effort: already_in_stack ? "low" : "medium",
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

    def fit_prose(entry:, signal:, already_in_stack:, match:)
      required = Array(entry.try(:required_systems)).presence
      caps = Array(entry.try(:capabilities)).first(3)
      parts = []
      parts << if already_in_stack
                 "#{entry.name} appears adjacent to systems already in #{@company.display_name || @company.name}'s stack, so rollout can extend existing tooling rather than introduce a greenfield platform."
               else
                 "#{entry.name} is a candidate capability for the friction around \"#{signal.label}\"."
               end
      parts << "It aligns with required systems (#{required.join(', ')})." if required
      parts << "Relevant capabilities: #{caps.join(', ')}." if caps.any?
      reason = match[:reason].to_s
      parts << "Match basis: #{reason.truncate(100)}." if reason.present?
      parts.join(" ")
    end
  end
end
