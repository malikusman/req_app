# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportReadinessCalculator do
  describe ".call" do
    let(:company) do
      create(
        :company,
        report_readiness_breakdown: {
          "employees_interviewed" => 3,
          "departments_represented" => 2,
          "confirmed_patterns" => 1,
          "multimodal_contributions" => 1
        }
      )
    end

    it "updates report_readiness_score on the company" do
      score = described_class.call(company)
      company.reload

      expect(score).to be_between(0, 100)
      expect(company.report_readiness_score).to eq(score)
    end

    it "returns 0 when thresholds are zero" do
      company.update!(settings: company.settings.merge("report_thresholds" => {
        "min_employees_interviewed" => 0,
        "min_departments" => 0,
        "min_patterns" => 0,
        "min_multimodal_contributions" => 0
      }))

      expect(described_class.call(company)).to eq(0.0)
    end
  end
end
