# frozen_string_literal: true

module Reports
  # Everything the consultant contributed, gathered in one place so the full
  # report and the executive brief render the SAME expert content.
  #
  # This exists because the expert-validated opportunity figure — the single
  # number an owner most wants, entered by the exact person whose credibility we
  # sell — reached the company dashboard and no PDF. It was collected and then
  # dropped. Now it leads both documents.
  #
  # Read-only over submitted reviews. Nothing here mutates the snapshot.
  class ExpertLayer
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
    end

    def call
      reviews = submitted_reviews
      return nil if reviews.empty?

      {
        "opportunity" => opportunity(reviews),
        "verdict" => verdict(reviews),
        "validators" => reviews.map { |r| validator(r) },
        "endorsed_section_keys" => endorsed_section_keys(reviews),
        "reviewed_at" => reviews.filter_map(&:submitted_at).max&.iso8601
      }.compact
    end

    private

    def submitted_reviews
      @report.report_reviews.submitted
             .includes(:consultant_user, :report_review_findings, :report_review_section_states)
             .to_a
    end

    # The highest expert-validated figure with a written basis. Several
    # consultants may each size it; the report leads with the best-evidenced one
    # rather than silently averaging numbers that were reasoned differently.
    def opportunity(reviews)
      sized = reviews.select { |r| r.opportunity_amount.to_i.positive? }
      return nil if sized.empty?

      best = sized.max_by { |r| r.opportunity_amount.to_i }
      {
        "amount" => best.opportunity_amount.to_i,
        "unit" => best.opportunity_unit.presence || "AED / year",
        "basis" => best.opportunity_basis.presence,
        "consultant" => best.consultant_user.name,
        "consultant_credential" => credential_for(best.consultant_user),
        "corroborated_by" => sized.size - 1
      }.compact
    end

    # The consultant's own answer to the client's question. SubmitService already
    # requires a publishable "executive_conclusion" finding, so this is present on
    # every properly submitted review.
    def verdict(reviews)
      finding = reviews.flat_map { |r|
        r.report_review_findings.select { |f| f.finding_type == "executive_conclusion" && f.publishable? }
         .map { |f| [r, f] }
      }.first
      return nil unless finding

      review, conclusion = finding
      {
        "body" => conclusion.body,
        "title" => conclusion.try(:title).presence,
        "recommendation" => conclusion.try(:recommendation).presence,
        "consultant" => review.consultant_user.name,
        "consultant_credential" => credential_for(review.consultant_user),
        "overall_note" => review.overall_note.presence
      }.compact
    end

    def validator(review)
      consultant = review.consultant_user
      {
        "name" => consultant.name,
        "credential" => credential_for(consultant),
        "years_experience" => consultant.try(:years_experience),
        "expertise_tags" => Array(consultant.try(:expertise_tags)).first(3),
        "status" => review.status,
        "submitted_at" => review.submitted_at&.iso8601
      }.compact
    end

    def endorsed_section_keys(reviews)
      reviews.flat_map { |r|
        r.report_review_section_states.select { |s| s.status == "approved" }.map(&:section_key)
      }.uniq
    end

    # Duplicated intentionally narrow: ReviewNotesCollector#credential_for builds
    # the same string for the appendix. Kept as one shared method here would drag
    # the appendix collector into this service's object graph for no gain.
    def credential_for(consultant)
      parts = []
      parts << consultant.headline.to_s.strip if consultant.try(:headline).present?
      if parts.empty? && consultant.try(:years_experience).to_i.positive?
        parts << "#{consultant.years_experience}+ years experience"
      end
      parts << Array(consultant.try(:expertise_tags)).first(3).join(", ") if Array(consultant.try(:expertise_tags)).any?
      parts.reject(&:blank?).join(" · ").presence || "Independent expert consultant"
    end
  end
end
