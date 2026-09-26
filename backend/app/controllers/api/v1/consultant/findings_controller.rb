# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # Consultant review of role-by-role findings: approve, hide, reword, merge.
      #
      # Merging is how effort is de-duplicated for now. When two people describe the
      # same work, one finding is merged into the other and its hours stop counting —
      # without it, the same effort is counted under both, and every capacity figure
      # in the report is overstated. Masood's Document 04 accepts a simple form for
      # V1; this is it.
      class FindingsController < BaseController
        before_action :set_company
        before_action :set_finding, only: %i[update merge]

        def index
          findings = @company.findings.includes(:employee, :reviewed_by, :merged_into)
                             .order(:department, :role_title, :area, :id)
          render json: { findings: findings.map { |f| finding_json(f) }, summary: summary(findings) }
        end

        def update
          attrs = params.require(:finding).permit(
            :status, :consultant_title, :consultant_what_happens_now, :consultant_friction, :consultant_note
          )
          if attrs[:status].present? && !%w[draft approved hidden].include?(attrs[:status])
            return render json: { error: "Use merge to merge a finding" }, status: :unprocessable_entity
          end

          # Reverting to draft or approving also un-merges: those are the two ways a
          # consultant says "this stands on its own after all".
          attrs[:merged_into_id] = nil if attrs[:status].present?
          @finding.assign_attributes(attrs)
          stamp_review!
          @finding.save!
          render json: { finding: finding_json(@finding.reload) }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end

        # POST .../findings/:id/merge { into_id } — this finding describes the same
        # work as `into`, so its hours must not be counted twice.
        def merge
          target = @company.findings.find(params.require(:into_id))
          @finding.assign_attributes(status: "merged", merged_into: target)
          stamp_review!
          Finding.transaction do
            @finding.save!
            # Anything already merged into this one follows it to the new target, so
            # merges never chain.
            @company.findings.where(merged_into_id: @finding.id).update_all(merged_into_id: target.id)
          end
          render json: { finding: finding_json(@finding.reload) }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end

        private

        def set_company
          @company = ::Company.find(params[:company_id])
          raise ActiveRecord::RecordNotFound unless assigned_company_ids.include?(@company.id)
        end

        def set_finding
          @finding = @company.findings.find(params[:id])
        end

        def stamp_review!
          @finding.reviewed_by = current_consultant_user
          @finding.reviewed_at = Time.current
        end

        def summary(findings)
          live = findings.reject { |f| %w[hidden merged].include?(f.status) }
          with_hours = live.select(&:hours?)
          {
            live_count: live.size,
            approved_count: live.count { |f| f.status == "approved" },
            merged_count: findings.count { |f| f.status == "merged" },
            hidden_count: findings.count { |f| f.status == "hidden" },
            needs_review_count: live.count(&:needs_review?),
            quantified_count: with_hours.size,
            # De-duplicated: merged and hidden findings never count.
            annual_hours_min: with_hours.sum(&:annual_hours_min),
            annual_hours_max: with_hours.sum(&:annual_hours_max)
          }
        end

        def finding_json(finding)
          {
            id: finding.id,
            department: finding.department,
            role_title: finding.role_title,
            area: finding.area,
            title: finding.display_title,
            what_happens_now: finding.display_what_happens_now,
            friction: finding.display_friction,
            # The interview's own words, so an edit can always be compared with them.
            original: { title: finding.title, what_happens_now: finding.what_happens_now, friction: finding.friction },
            consultant: {
              title: finding.consultant_title,
              what_happens_now: finding.consultant_what_happens_now,
              friction: finding.consultant_friction,
              note: finding.consultant_note
            },
            frequency: { as_said: finding.frequency_as_said, min: finding.frequency_min&.to_f,
                         max: finding.frequency_max&.to_f, unit: finding.frequency_unit },
            duration: { as_said: finding.duration_as_said, min: finding.duration_min&.to_f,
                        max: finding.duration_max&.to_f, unit: finding.duration_unit },
            effort_type: finding.effort_type,
            annual_hours: finding.hours? ? { min: finding.annual_hours_min, max: finding.annual_hours_max } : nil,
            hours_basis: finding.hours_basis,
            basis: finding.basis,
            confidence: finding.confidence,
            single_occupant_role: finding.single_occupant_role,
            needs_review: finding.needs_review?,
            status: finding.status,
            merged_into_id: finding.merged_into_id,
            employee: finding.employee && { id: finding.employee.id, name: finding.employee.display_name },
            conversation_id: finding.conversation_id,
            reviewed_at: finding.reviewed_at,
            reviewed_by: finding.reviewed_by&.name
          }
        end
      end
    end
  end
end
