# frozen_string_literal: true

module Api
  module V1
    module Reviewer
      # Reviewer editorial control over the report body: hide a built-in section,
      # add an editorial note to one, or add a whole new custom section. Applied at
      # regeneration time; the stored snapshot is never mutated.
      class ReportSectionOverridesController < BaseController
        before_action :load_report

        def index
          overrides = @report.report_section_overrides.order(:position, :created_at)
          render json: {
            built_in_sections: ReportSectionOverride::BUILT_IN_SECTIONS,
            overrides: overrides.map { |o| serialize(o) }
          }
        end

        def create
          override = @report.report_section_overrides.new(override_params)
          override.reviewer_user = current_reviewer_user
          override.save!
          render json: { override: serialize(override) }, status: :created
        end

        def update
          override = owned_override
          override.update!(override_params)
          render json: { override: serialize(override) }
        end

        def destroy
          owned_override.destroy!
          head :no_content
        end

        private

        def load_report
          @report = policy_scope(::Report).find(params[:report_id])
        end

        # Reviewers may only edit their own overrides.
        def owned_override
          @report.report_section_overrides.find_by!(id: params[:id], reviewer_user_id: current_reviewer_user.id)
        end

        def override_params
          params.require(:section_override)
                .permit(:action, :section_key, :anchor_section, :title, :body, :position, :published)
        end

        def serialize(o)
          {
            id: o.id,
            action: o.action,
            section_key: o.section_key,
            anchor_section: o.anchor_section,
            title: o.title,
            body: o.body,
            position: o.position,
            published: o.published,
            reviewer_name: o.reviewer_user&.name,
            editable: o.reviewer_user_id == current_reviewer_user.id
          }
        end
      end
    end
  end
end
