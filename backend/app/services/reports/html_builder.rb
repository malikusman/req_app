# frozen_string_literal: true

module Reports
  class HtmlBuilder
    def self.call(snapshot:, review_notes: nil)
      new(snapshot: snapshot, review_notes: review_notes).call
    end

    def initialize(snapshot:, review_notes: nil)
      @snapshot = snapshot
      @review_notes = review_notes
    end

    def call
      ActionController::Base.render(
        template: "reports/document",
        layout: false,
        locals: {
          snapshot: @snapshot,
          review_notes: Array(@review_notes),
          generated_label: generated_label
        }
      )
    end

    private

    def generated_label
      timestamp = @snapshot["generated_at"]
      return Time.current.strftime("%B %d, %Y") if timestamp.blank?

      Time.zone.parse(timestamp.to_s).strftime("%B %d, %Y")
    rescue ArgumentError
      Time.current.strftime("%B %d, %Y")
    end
  end
end
