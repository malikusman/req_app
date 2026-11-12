# frozen_string_literal: true

module Synthesis
  # Where an engagement's synthesis stands, worked out from its runs and what
  # is waiting on the consultant — nothing is stored on the engagement itself.
  #
  #   not_started   no run yet
  #   queued        a run is waiting (new evidence arrived; runs are debounced)
  #   running       a run is in progress
  #   failed        the only runs failed
  #   stale         evidence changed since the latest finished run
  #   needs_review  the latest synthesis has items waiting on the consultant
  #   approved      everything current has been decided
  module Status
    module_function

    def for(engagement)
      runs = SynthesisRun.where(engagement: engagement).order(version: :desc)
      latest = runs.first
      finished = runs.finished.first
      review = review_counts(engagement, finished)
      state = if latest.nil? then "not_started"
              elsif latest.status == "QUEUED" then "queued"
              elsif latest.status == "RUNNING" then "running"
              elsif finished.nil? then "failed"
              elsif finished.input_digest != Run.input_digest(engagement) then "stale"
              elsif review.values.sum.positive? then "needs_review"
              else "approved"
              end
      { "state" => state, "latest_run" => latest, "latest_finished_run" => finished, "review" => review }
    end

    def review_counts(engagement, run)
      scope = { engagement_id: engagement.id }
      {
        "clusters" => SynthesisCluster.current.where(scope).where(status: "PROVISIONAL").count,
        "pairs" => ProcessRelationship.current.where(scope)
                                      .where("origin = 'FALLBACK' OR recommendation IN ('CONSULTANT_REVIEW', 'CLARIFY')")
                                      .count,
        "opportunities" => ConsultancyOpportunity.current.where(scope).where(status: "PROPOSED").count,
        "root_causes" => RootCause.current.where(scope).where(status: "PROPOSED").count,
        "validations" => ManagementValidation.current.where(scope).where(status: "PROPOSED").count,
        "operating_picture" => run && run.operating_picture.present? && run.operating_picture_status == "PROPOSED" ? 1 : 0
      }
    end
  end
end
