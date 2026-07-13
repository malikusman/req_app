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
            "multimodal_evidence" => s.metadata.fetch("multimodal_evidence", []),
            "source_excerpts" => s.metadata.fetch("source_excerpts", [])
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
        "supporting_media" => supporting_media_json,
        "supporting_documents" => supporting_documents_json,
        "tools_catalog" => tools_catalog_json
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

    def supporting_documents_json
      @company.documents.ready.order(created_at: :desc).limit(12).map do |doc|
        {
          "id" => doc.id,
          "filename" => doc.filename,
          "department" => doc.department,
          "document_type" => doc.try(:document_type),
          "sensitivity" => doc.try(:sensitivity),
          "source" => doc.source,
          "summary" => doc.insights_preview.is_a?(Hash) ? doc.insights_preview["summary"] : nil,
          "chunk_count" => doc.insights_preview.is_a?(Hash) ? doc.insights_preview["chunk_count"] : nil
        }
      end
    end

    def tools_catalog_json
      curated = []

      if defined?(CompanyCatalogMatch) && CompanyCatalogMatch.table_exists?
        curated = CompanyCatalogMatch
          .where(company_id: @company.id)
          .includes(:solution_catalog_entry)
          .order(score: :desc)
          .limit(12)
          .map do |match|
            entry = match.solution_catalog_entry
            {
              "solution_id" => entry.id,
              "name" => entry.name,
              "vendor" => entry.vendor,
              "category" => entry.category,
              "url" => entry.website_url,
              "partnership_tier" => entry.partnership_tier,
              "reason" => match.why_it_fits,
              "score" => match.score,
              "matched_at" => match.matched_at
            }
          end
      end

      if curated.empty?
        matches = @company.recommendations.published.flat_map { |r| Array(r.catalog_matches) }
        curated = matches.filter_map do |m|
          next unless m.is_a?(Hash)

          {
            "solution_id" => m["solution_id"] || m[:solution_id],
            "name" => m["name"] || m[:name],
            "vendor" => m["vendor"] || m[:vendor],
            "category" => m["category"] || m[:category],
            "url" => m["url"] || m[:url],
            "partnership_tier" => m["partnership_tier"] || m[:partnership_tier],
            "reason" => m["reason"] || m[:reason]
          }
        end.uniq { |m| m["solution_id"] || m["name"] }
      end

      endorsements = []
      if defined?(CatalogEndorsement) && CatalogEndorsement.table_exists?
        endorsements = CatalogEndorsement
          .where(company_id: @company.id, publishable: true)
          .includes(:solution_catalog_entry, :reviewer_user)
          .order(created_at: :desc)
          .limit(20)
          .map do |e|
            entry = e.solution_catalog_entry
            {
              "disposition" => e.disposition,
              "rationale" => e.rationale,
              "source_url" => e.source_url,
              "solution_catalog_entry_id" => e.solution_catalog_entry_id,
              "solution_name" => entry&.name,
              "solution_vendor" => entry&.vendor,
              "reviewer_user_id" => e.reviewer_user_id,
              "reviewer_name" => e.reviewer_user&.name,
              "created_at" => e.created_at&.iso8601
            }
          end
      end

      # Attach publishable endorsements onto matching curated tools when possible.
      curated = curated.map do |tool|
        related = endorsements.select { |e| e["solution_catalog_entry_id"].to_i == tool["solution_id"].to_i }
        tool.merge("endorsements" => related)
      end

      {
        "curated_matches" => curated.first(8),
        "endorsements" => endorsements,
        "disclaimer" => "Catalog suggestions are advisory. Reviewer-validated picks appear with endorsement notes below."
      }
    end
  end
end
