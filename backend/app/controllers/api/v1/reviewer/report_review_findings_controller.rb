# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      class ReportReviewFindingsController < BaseController
        before_action :load_review

        def index
          authorize @review, :show?
          findings = @review.report_review_findings.order(:created_at)
          render json: { findings: findings.map { |f| finding_json(f) } }
        end

        def create
          finding = @review.report_review_findings.build(
            finding_params.merge(reviewer_user: current_reviewer_user)
          )
          authorize finding, :create?
          finding.save!
          render json: { finding: finding_json(finding) }, status: :created
        end

        def update
          finding = @review.report_review_findings.find(params[:id])
          authorize finding, :update?
          finding.update!(finding_params)
          render json: { finding: finding_json(finding) }
        end

        def destroy
          finding = @review.report_review_findings.find(params[:id])
          authorize finding, :destroy?
          finding.destroy!
          head :no_content
        end

        private

        def load_review
          report = policy_scope(::Report).find(params[:report_id])
          @review = ReportReview.find_by!(report: report, reviewer_user: current_reviewer_user)
        end

        def finding_params
          params.require(:finding).permit(
            :finding_type, :section_key, :target_type, :target_id, :disposition,
            :severity, :body, :publishable, :resolution_status, evidence_refs: []
          )
        end

        def finding_json(f)
          {
            id: f.id,
            report_review_id: f.report_review_id,
            reviewer_user_id: f.reviewer_user_id,
            finding_type: f.finding_type,
            section_key: f.section_key,
            target_type: f.target_type,
            target_id: f.target_id,
            disposition: f.disposition,
            severity: f.severity,
            body: f.body,
            evidence_refs: f.evidence_refs,
            publishable: f.publishable,
            resolution_status: f.resolution_status,
            created_at: f.created_at,
            updated_at: f.updated_at
          }
        end
      end
    end
  end
end
