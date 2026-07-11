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
      matches = []
      @company.company_signals.order(strength: :desc).limit(20).each do |signal|
        Intelligence::CatalogMatcher.call(signal: signal).each do |match|
          entry = SolutionCatalogEntry.find_by(id: match[:solution_id])
          next unless entry

          record = CompanyCatalogMatch.find_or_initialize_by(
            company: @company,
            solution_catalog_entry_id: entry.id
          )
          record.assign_attributes(
            score: match[:score] || 0,
            why_it_fits: match[:reason],
            evidence_used: [{ "signal_id" => signal.id, "label" => signal.label }],
            assumptions: [],
            risks: ["Catalog suggestion is advisory until reviewer endorsement"],
            estimated_effort: "medium",
            validate_next: "Confirm systems and security constraints with stakeholders",
            catalog_version: entry.updated_at.iso8601,
            matched_at: Time.current
          )
          record.save!
          matches << record
        end
      end
      matches
    end
  end
end
