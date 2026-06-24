# frozen_string_literal: true

module Reports
  class ReviewNotesCollector
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
    end

    def call
      @report.report_reviews.includes(:reviewer_user, :report_review_comments).flat_map do |review|
        notes = []
        if review.overall_note.present?
          notes << {
            "reviewer" => review.reviewer_user.name,
            "section_key" => nil,
            "body" => review.overall_note
          }
        end

        review.report_review_comments.order(:created_at).each do |comment|
          notes << {
            "reviewer" => review.reviewer_user.name,
            "section_key" => comment.section_key,
            "body" => comment.body
          }
        end

        notes
      end
    end
  end
end
