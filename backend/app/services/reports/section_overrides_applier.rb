# frozen_string_literal: true

module Reports
  # Applies consultant section overrides to a COPY of the stored snapshot at
  # regenerate time. The persisted snapshot is never mutated, so the AI body and
  # the expert edits remain separable and auditable.
  class SectionOverridesApplier
    def self.call(snapshot:, report:)
      new(snapshot: snapshot, report: report).call
    end

    def initialize(snapshot:, report:)
      @snapshot = snapshot
      @report = report
    end

    def call
      overrides = load_overrides
      expert = Reports::ExpertLayer.call(report: @report)
      return @snapshot if overrides.blank? && expert.blank?

      snap = deep_dup(@snapshot)
      # The consultant's own verdict and the opportunity figure they sized. Lives
      # on the render-time copy for the same reason overrides do: reviews are
      # submitted AFTER the snapshot is generated, and the stored snapshot must
      # stay the untouched machine analysis.
      snap["expert"] = expert if expert.present?
      applied_edits = edits(overrides)
      snap["section_overrides"] = {
        "hidden" => hidden_keys(overrides),
        "edits" => applied_edits,
        "custom" => custom_sections(overrides)
      }

      # The executive summary also feeds the cover subtitle / contents teaser, so
      # when a consultant rewrites it, propagate the edit to the base field too — the
      # whole deliverable should reflect the expert's version, not the AI's.
      exec_body = applied_edits.dig("executive_summary", "body")
      snap["executive_summary"] = exec_body if exec_body.to_s.strip.present?

      snap
    end

    private

    def load_overrides
      return [] unless ReportSectionOverride.table_exists?

      @report.report_section_overrides.published.order(:position, :created_at).includes(:consultant_user).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def hidden_keys(overrides)
      overrides.select { |o| o.action == "hide" }.map(&:section_key).uniq
    end

    def edits(overrides)
      overrides.select { |o| o.action == "edit" }.each_with_object({}) do |o, h|
        h[o.section_key] = {
          "title" => o.title.presence,
          "body" => o.body,
          "consultant" => o.consultant_user&.name,
          "consultant_credential" => credential_for(o.consultant_user)
        }
      end
    end

    def custom_sections(overrides)
      overrides.select { |o| o.action == "add" }.map do |o|
        template = ReportSectionTemplates.find(o.section_key)
        {
          "slug" => o.custom_slug,
          "section_key" => o.section_key.presence,
          "title" => o.title,
          "body" => o.body,
          # A section added from the library carries the library's one-line
          # statement of what the section is for, so the page explains itself.
          "purpose" => template && template["purpose"],
          "anchor_section" => o.anchor_section.presence,
          "position" => o.position,
          "consultant" => o.consultant_user&.name,
          "consultant_credential" => credential_for(o.consultant_user)
        }
      end
    end

    def credential_for(consultant)
      return nil unless consultant

      parts = []
      parts << consultant.headline.to_s.strip if consultant.try(:headline).present?
      if parts.empty? && consultant.try(:years_experience).to_i.positive?
        parts << "#{consultant.years_experience}+ years experience"
      end
      parts << Array(consultant.try(:expertise_tags)).first(3).join(", ") if Array(consultant.try(:expertise_tags)).any?
      parts.reject(&:blank?).join(" · ").presence || "Independent expert consultant"
    end

    def deep_dup(obj)
      case obj
      when Hash then obj.transform_values { |v| deep_dup(v) }
      when Array then obj.map { |v| deep_dup(v) }
      else obj
      end
    end
  end
end
