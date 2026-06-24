# frozen_string_literal: true

module Reports
  class SnapshotBuilder
    def self.call(company:, delta:)
      new(company: company, delta: delta).call
    end

    def initialize(company:, delta:)
      @company = company
      @delta = delta
    end

    def call
      {
        "generated_at" => Time.current.iso8601,
        "company" => {
          "name" => @company.display_name || @company.name,
          "locale" => @company.locale
        },
        "readiness" => {
          "score" => @company.report_readiness_score,
          "breakdown" => @company.report_readiness_breakdown
        },
        "participation" => Intelligence::SnapshotBuilder.call(company: @company)["participation"],
        "signals" => @company.company_signals.order(strength: :desc).map do |s|
          {
            "id" => s.id,
            "label" => s.label,
            "strength" => s.strength,
            "departments" => s.departments,
            "signal_type" => s.signal_type,
            "evidence_count" => s.evidence_count,
            "multimodal_evidence" => s.metadata.fetch("multimodal_evidence", [])
          }
        end,
        "patterns" => @company.patterns.order(confidence: :desc).map do |p|
          { "id" => p.id, "title" => p.title, "description" => p.description, "confidence" => p.confidence }
        end,
        "recommendations" => @company.recommendations.published.visible_to_company.map do |r|
          {
            "id" => r.id,
            "title" => r.title,
            "description" => r.description,
            "implementation_outline" => r.implementation_outline,
            "catalog_matches" => r.catalog_matches,
            "priority" => r.priority
          }
        end,
        "delta_from_previous" => @delta,
        "executive_summary" => executive_summary,
        "sections" => ReportSections::DEFINITIONS,
        "supporting_media" => supporting_media_json
      }
    end

    private

    def executive_summary
      participation = Intelligence::SnapshotBuilder.call(company: @company)["participation"] || {}
      invited = participation["invited"].to_i
      completed = participation["completed"].to_i
      parts = ["#{completed} of #{invited} employees completed discovery interviews."]

      top_signals = @company.company_signals.order(strength: :desc).limit(3).pluck(:label)
      parts << "Top friction areas include #{top_signals.join(', ')}." if top_signals.any?

      pattern_count = @company.patterns.count
      parts << "#{pattern_count} cross-team #{'pattern'.pluralize(pattern_count)} inform the recommendations below." if pattern_count.positive?

      parts.join(" ")
    end

    def supporting_media_json
      MediaAttachment.where(company_id: @company.id, status: "ready")
                     .includes(:employee)
                     .order(created_at: :desc)
                     .limit(20)
                     .map do |attachment|
        insights = attachment.structured_insights.presence || {}
        {
          "id" => attachment.id,
          "attachment_type" => attachment.attachment_type,
          "caption" => attachment.caption,
          "summary" => insights["summary"].presence || attachment.extracted_text.to_s.truncate(200),
          "conversation_id" => attachment.conversation_id,
          "employee_department" => attachment.employee.department,
          "confidence" => attachment.confidence
        }
      end
    end
  end
end
