# frozen_string_literal: true

module Reports
  # Applies reviewer section overrides to a COPY of the stored snapshot at
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
      return @snapshot if overrides.blank?

      snap = deep_dup(@snapshot)
      applied_edits = edits(overrides)
      snap["section_overrides"] = {
        "hidden" => hidden_keys(overrides),
        "edits" => applied_edits,
        "custom" => custom_sections(overrides)
      }

      # The executive summary also feeds the cover subtitle / contents teaser, so
      # when a reviewer rewrites it, propagate the edit to the base field too — the
      # whole deliverable should reflect the expert's version, not the AI's.
      exec_body = applied_edits.dig("executive_summary", "body")
      snap["executive_summary"] = exec_body if exec_body.to_s.strip.present?

      snap
    end

    private

    def load_overrides
      return [] unless ReportSectionOverride.table_exists?

      @report.report_section_overrides.published.order(:position, :created_at).includes(:reviewer_user).to_a
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
          "reviewer" => o.reviewer_user&.name
        }
      end
    end

    def custom_sections(overrides)
      overrides.select { |o| o.action == "add" }.map do |o|
        {
          "slug" => o.custom_slug,
          "title" => o.title,
          "body" => o.body,
          "anchor_section" => o.anchor_section.presence,
          "position" => o.position,
          "reviewer" => o.reviewer_user&.name
        }
      end
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
