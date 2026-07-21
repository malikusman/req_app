# frozen_string_literal: true

module Intelligence
  # Upserts client stack tools from employees + document insights.
  class CompanyStackInferrer
    CATEGORY_HINTS = {
      "sap" => "erp",
      "oracle" => "erp",
      "netsuite" => "erp",
      "excel" => "spreadsheet",
      "google sheets" => "spreadsheet",
      "sheets" => "spreadsheet",
      "tms" => "tms",
      "manhattan" => "warehouse",
      "whatsapp" => "messaging",
      "slack" => "messaging",
      "teams" => "messaging",
      "salesforce" => "crm",
      "hubspot" => "crm"
    }.freeze

    def self.call(company:)
      new(company: company).call
    end

    def initialize(company:)
      @company = company
    end

    def call
      upserted = []
      collect_from_employees.each { |row| upserted << upsert!(row) }
      collect_from_documents.each { |row| upserted << upsert!(row) }
      upserted.compact
    end

    private

    def collect_from_employees
      @company.employees.find_each.flat_map do |employee|
        tools = Array(employee.metadata.dig("profile", "primary_tools"))
        tools = Array(employee.metadata["primary_tools"]) if tools.blank?
        tools.filter_map do |name|
          next if name.blank?

          {
            name: name.to_s.strip,
            source: "inferred_employee",
            confidence: 0.7,
            category: category_for(name)
          }
        end
      end
    end

    def collect_from_documents
      @company.documents.where(status: "ready").find_each.flat_map do |doc|
        preview = doc.insights_preview.is_a?(Hash) ? doc.insights_preview : {}
        tools = Array(preview["tools_mentioned"]) + Array(preview["systems"]) + Array(preview["tools_visible"])
        tools.filter_map do |name|
          next if name.blank?

          {
            name: name.to_s.strip,
            source: "inferred_document",
            confidence: 0.6,
            category: category_for(name)
          }
        end
      end
    end

    def upsert!(row)
      normalized = CompanySystem.normalize(row[:name])
      return if normalized.blank?

      record = @company.company_systems.find_or_initialize_by(normalized_name: normalized)
      if record.new_record?
        record.assign_attributes(
          name: row[:name],
          category: row[:category],
          source: row[:source],
          confidence: row[:confidence],
          active: true
        )
      else
        # Prefer manual records; otherwise raise confidence / keep richer name casing.
        unless record.source == "manual"
          record.confidence = [record.confidence.to_f, row[:confidence].to_f].max
          record.category = row[:category] if record.category == "other" && row[:category] != "other"
        end
      end
      record.save!
      record
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def category_for(name)
      key = CompanySystem.normalize(name)
      CATEGORY_HINTS.each do |hint, category|
        return category if key.include?(hint)
      end
      "other"
    end
  end
end
