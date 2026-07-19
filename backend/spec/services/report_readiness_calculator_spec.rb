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

    it "scores docs phase at 100 when document thresholds are met" do
      company.update!(
        settings: company.settings.merge(
          "engagement_mode" => "documents",
          "report_thresholds" => {
            "min_ready_documents" => 3,
            "min_document_departments" => 2,
            "min_patterns" => 1,
            "min_multimodal_contributions" => 1
          }
        ),
        report_readiness_breakdown: {
          "employees_interviewed" => 0,
          "ready_documents" => 3,
          "document_departments" => 2,
          "confirmed_patterns" => 1,
          "multimodal_contributions" => 3
        }
      )

      expect(described_class.call(company)).to eq(100.0)
      expect(described_class.new(company).docs_phase?).to eq(true)
    end

    it "uses full interview weights when interview blend reaches 1.0" do
      company.update!(
        settings: company.settings.merge("engagement_mode" => "hybrid"),
        report_readiness_breakdown: {
          "employees_interviewed" => 3,
          "departments_represented" => 2,
          "confirmed_patterns" => 1,
          "multimodal_contributions" => 1,
          "ready_documents" => 0,
          "document_departments" => 0
        }
      )

      expect(described_class.new(company).docs_phase?).to eq(false)
      expect(described_class.new(company).interview_blend).to eq(1.0)
      expect(described_class.call(company)).to eq(100.0)
    end

    it "stays in docs phase for hybrid with zero interviews" do
      company.update!(
        settings: company.settings.merge("engagement_mode" => "hybrid"),
        report_readiness_breakdown: {
          "employees_interviewed" => 0,
          "ready_documents" => 3,
          "document_departments" => 1,
          "confirmed_patterns" => 1,
          "multimodal_contributions" => 1
        }
      )

      expect(described_class.new(company).docs_phase?).to eq(true)
    end

    it "does not cliff from 100 when the first interview completes with a strong docs baseline" do
      company.update!(
        settings: company.settings.merge(
          "engagement_mode" => "hybrid",
          "report_thresholds" => {
            "min_employees_interviewed" => 3,
            "min_departments" => 2,
            "min_patterns" => 1,
            "min_multimodal_contributions" => 1,
            "min_ready_documents" => 3,
            "min_document_departments" => 2
          }
        ),
        report_readiness_breakdown: {
          "employees_interviewed" => 0,
          "ready_documents" => 3,
          "document_departments" => 2,
          "confirmed_patterns" => 1,
          "multimodal_contributions" => 3
        }
      )
      docs_score = described_class.call(company)
      expect(docs_score).to eq(100.0)

      company.update!(
        report_readiness_breakdown: company.report_readiness_breakdown.merge(
          "employees_interviewed" => 1,
          "departments_represented" => 1
        )
      )
      after = described_class.call(company.reload)

      expect(described_class.new(company).interview_blend).to be_within(0.01).of(1.0 / 3.0)
      expect(after).to be >= 80.0
      expect(after).to be < docs_score
    end
  end
end
