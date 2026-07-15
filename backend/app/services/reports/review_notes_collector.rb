# frozen_string_literal: true

module Reports
  # Collects publishable reviewer overlay for PDF regeneration.
  # Layer C only — never mutates derived intelligence.
  class ReviewNotesCollector
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
    end

    def call
      reviews = @report.report_reviews
        .submitted
        .includes(:reviewer_user, :report_review_comments, :report_review_section_states)

      reviews.flat_map { |review| notes_for(review) }
    end

    def overlay(report: @report)
      reviews = report.report_reviews
        .submitted
        .includes(
          :reviewer_user,
          :report_review_comments,
          :report_review_section_states,
          report_review_findings: []
        )

      {
        "notes" => reviews.flat_map { |review| notes_for(review) },
        "section_dispositions" => reviews.flat_map { |review| dispositions_for(review) },
        "structured_findings" => reviews.flat_map { |review| findings_for(review) }
      }
    end

    private

    def notes_for(review)
      notes = []
      if review.overall_note.present?
        notes << {
          "reviewer" => review.reviewer_user.name,
          "section_key" => nil,
          "body" => review.overall_note,
          "kind" => "overall_note",
          "resolved" => false,
          "publishable" => true
        }
      end

      review.report_review_comments.order(:created_at).each do |comment|
        next if comment.resolved?

        notes << {
          "reviewer" => review.reviewer_user.name,
          "section_key" => comment.section_key,
          "body" => comment.body,
          "kind" => "section_comment",
          "resolved" => false,
          "publishable" => true
        }
      end

      notes
    end

    def dispositions_for(review)
      review.report_review_section_states.map do |state|
        {
          "reviewer" => review.reviewer_user.name,
          "section_key" => state.section_key,
          "disposition" => state.status,
          "comment" => state.try(:comment).presence || state.try(:notes).presence
        }
      end
    end

    def findings_for(review)
      return [] unless review.respond_to?(:report_review_findings)
      return [] unless ActiveRecord::Base.connection.data_source_exists?("report_review_findings")

      review.report_review_findings.select(&:publishable?).map do |finding|
        {
          "reviewer" => review.reviewer_user.name,
          "kind" => finding.finding_type,
          "finding_type" => finding.finding_type,
          "title" => finding.try(:title).presence || finding.finding_type.to_s.humanize,
          "section_key" => finding.section_key,
          "disposition" => finding.disposition,
          "severity" => finding.severity,
          "body" => finding.body,
          "recommendation" => finding.try(:recommendation),
          "target_type" => finding.target_type,
          "target_id" => finding.target_id,
          "evidence_refs" => finding.evidence_refs
        }
      end
    end
  end
end
