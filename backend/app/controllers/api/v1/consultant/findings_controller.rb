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
          render json: { findings: findings.map { |f| finding_json(f) }, summary: summary(findings),
                         intervention_types: Finding::INTERVENTION_TYPES.map { |key, label| { key: key, label: label } } }
        end

        def update
          attrs = params.require(:finding).permit(
            :status, :consultant_title, :consultant_what_happens_now, :consultant_friction, :consultant_note,
            :consultant_cause, :consultant_cause_stated, :consultant_intervention_type, :consultant_direction,
            :consultant_dependency, consultant_depends_on_ids: [],
            consultant_effort: [:effort_type, { frequency: %i[min max unit], duration: %i[min max unit] }]
          )
          # An empty correction ({} or null) puts the interview's figures back.
          attrs[:consultant_effort] = {} if params[:finding].key?(:consultant_effort) && attrs[:consultant_effort].blank?
          # Links: null follows the drafted links again; a list, even empty, is the
          # consultant's own.
          if params[:finding].key?(:consultant_depends_on_ids)
            ids = params[:finding][:consultant_depends_on_ids]
            attrs[:consultant_depends_on_ids] = ids.nil? ? nil : Array(ids).map(&:to_i).uniq
          end
          if attrs[:status].present? && !%w[draft approved hidden].include?(attrs[:status])
            return render json: { error: "Use merge to merge a finding" }, status: :unprocessable_entity
          end

          # Reverting to draft or approving also un-merges: those are the two ways a
          # consultant says "this stands on its own after all".
          attrs[:merged_into_id] = nil if attrs[:status].present?
          @finding.assign_attributes(attrs)
          stamp_review!
          @finding.save!
          # Reworded: the drafted cause and direction no longer fit it.
          DraftFindingCausesJob.perform_later([@finding.id]) if @finding.draft_stale?
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
          # The same total the report prints: a probable double count is left out
          # until the consultant approves it as separate work or merges it.
          with_hours = live.select(&:hours?).reject { |f| f.status == "draft" && f.possible_duplicate_of_id }
          {
            live_count: live.size,
            approved_count: live.count { |f| f.status == "approved" },
            merged_count: findings.count { |f| f.status == "merged" },
            hidden_count: findings.count { |f| f.status == "hidden" },
            needs_review_count: live.count(&:needs_review?),
            quantified_count: with_hours.size,
            # De-duplicated: merged, hidden and probable-duplicate findings never count.
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
              note: finding.consultant_note,
              cause: finding.consultant_cause,
              cause_stated: finding.consultant_cause_stated,
              intervention_type: finding.consultant_intervention_type,
              direction: finding.consultant_direction,
              dependency: finding.consultant_dependency,
              # null while the drafted links stand; a list (even empty) once set.
              depends_on_ids: finding.consultant_depends_on_ids
            },
            # Why it happens, the kind of change and what must come first: the draft,
            # and what the report prints (the consultant's where they wrote one).
            drafted: { cause: finding.cause, cause_stated: finding.cause_stated,
                       intervention_type: finding.intervention_type, direction: finding.direction,
                       dependency: finding.dependency, depends_on_ids: finding.depends_on_ids },
            cause: finding.display_cause,
            cause_stated: finding.display_cause_stated,
            intervention_type: finding.display_intervention_type,
            direction: finding.display_direction,
            dependency: finding.display_dependency,
            depends_on_ids: finding.effective_depends_on_ids,
            draft_pending: finding.draft_stale?,
            frequency: { as_said: finding.frequency_as_said, min: finding.frequency_min&.to_f,
                         max: finding.frequency_max&.to_f, unit: finding.frequency_unit },
            duration: { as_said: finding.duration_as_said, min: finding.duration_min&.to_f,
                        max: finding.duration_max&.to_f, unit: finding.duration_unit },
            effort_type: finding.effort_type,
            # The consultant's correction of the figures, or null when the
            # interview's stand. Hours below are always from whichever applies.
            corrected_effort: finding.effort_corrected? ? finding.consultant_effort : nil,
            display_frequency: finding.display_frequency,
            display_duration: finding.display_duration,
            effective_effort_type: finding.effective_effort_type,
            annual_hours: finding.hours? ? { min: finding.annual_hours_min, max: finding.annual_hours_max } : nil,
            hours_basis: finding.hours_basis,
            basis: finding.basis,
            confidence: finding.confidence,
            single_occupant_role: finding.single_occupant_role,
            needs_review: finding.needs_review?,
            possible_duplicate_of_id: finding.possible_duplicate_of_id,
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
