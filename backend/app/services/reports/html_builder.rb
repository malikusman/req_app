# frozen_string_literal: true

module Reports
  # Thin controller so ActionView can load ReportsHelper for PDF HTML.
  class RenderController < ActionController::Base
    helper ReportsHelper
  end

  class HtmlBuilder
    def self.call(snapshot:, review_notes: nil, report_version: nil)
      new(snapshot: snapshot, review_notes: review_notes, report_version: report_version).call
    end

    def initialize(snapshot:, review_notes: nil, report_version: nil)
      @snapshot = snapshot
      @review_notes = review_notes
      @report_version = report_version
    end

    def call
      RenderController.render(
        template: "reports/document",
        layout: false,
        locals: {
          snapshot: @snapshot.is_a?(Hash) ? @snapshot.deep_stringify_keys : @snapshot,
          review_notes: Array(@review_notes),
          generated_label: generated_label,
          report_version: @report_version
        }
      )
    end

    private

    def generated_label
      timestamp = @snapshot.is_a?(Hash) ? @snapshot["generated_at"] || @snapshot[:generated_at] : nil
      return Time.current.strftime("%B %d, %Y") if timestamp.blank?

      Time.zone.parse(timestamp.to_s).strftime("%B %d, %Y")
    rescue ArgumentError
      Time.current.strftime("%B %d, %Y")
    end
  end
end
