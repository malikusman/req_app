# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # The conversations with leadership for a company the consultant is
      # assigned to (Doc 08): what each produced, and the few things a
      # consultant does about them — set a persona or a neutral focus before it
      # starts, send the invitation again, close one that won't finish, open a
      # further session, correct or reject a finding, and settle planned counts.
      class KeyPersonSessionsController < BaseController
        FINDING_FIELDS = %i[statement business_consequence category scope symptom_or_cause management_importance
                            validation_need].freeze

        before_action :set_engagement
        before_action :set_participant, only: %i[update_participant invite close further_session]

        def show
          render json: KeyPerson::ConsultantView.new(@engagement).json
        end

        def update_participant
          attrs = params.require(:participant).permit(:persona, :consultant_focus)
          @participant.update!(attrs)
          render json: KeyPerson::ConsultantView.new(@engagement).json
        end

        def invite
          unless KeyPerson::Invite.call(@participant)
            return render json: { error: "Add an email address for #{@participant.name} first" }, status: :unprocessable_entity
          end

          render json: KeyPerson::ConsultantView.new(@engagement).json
        end

        # A conversation that won't be finished: what was said is built into a
        # context all the same, and it no longer holds anything up.
        def close
          session = @participant.conversation_sessions.last
          return render json: { error: "There is no open conversation to close" }, status: :conflict if session.nil? || session.finished?

          session.with_lock do
            session.move_to("ABANDONED")
            session.update!(close_reason: "ABANDONED", completed_at: Time.current)
          end
          @participant.update!(participation_status: "ABANDONED")
          KeyPerson::Completion.call(session)
          render json: KeyPerson::ConsultantView.new(@engagement).json
        end

        # Another sitting with someone who has finished (Doc 08 §24): it picks up
        # the coverage and summary so far, and its context is a new version.
        def further_session
          previous = @participant.conversation_sessions.last
          unless previous&.finished?
            return render json: { error: "Their current conversation hasn't finished" }, status: :conflict
          end

          carried = previous.state_snapshot.slice("coverage", "summary")
          @participant.conversation_sessions.create!(
            company: @participant.company, engagement: @engagement, version: previous.version + 1,
            language: previous.language, limits: previous.limits, state_snapshot: carried
          )
          @participant.update!(participation_status: "INVITED")
          KeyPerson::Invite.call(@participant)
          render json: KeyPerson::ConsultantView.new(@engagement).json, status: :created
        end

        # A correction makes a new version and keeps the old one; a rejection is
        # kept, marked rejected (Doc 06 §1.2). Both need a reason (Doc 08 §30).
        def update_finding
          finding = StrategicFinding.where(engagement: @engagement).find(params[:id])
          rationale = params[:rationale].to_s.strip
          return render json: { error: "Say why" }, status: :unprocessable_entity if rationale.blank?

          StrategicFinding.transaction do
            if params[:reject].to_s == "true"
              finding.update!(status: "REJECTED", edited_by: current_consultant_user, edit_rationale: rationale)
            else
              changes = params.require(:finding).permit(*FINDING_FIELDS).to_h
              copy = finding.attributes.except("id", "created_at", "updated_at").merge(changes)
              StrategicFinding.create!(copy.merge("version" => finding.version + 1, "parent_version_id" => finding.id,
                                                  "status" => "ACTIVE", "edited_by" => current_consultant_user,
                                                  "edit_rationale" => rationale))
              finding.update!(status: "SUPERSEDED")
            end
          end
          render json: KeyPerson::ConsultantView.new(@engagement).json
        end

        # Counts agreed with the client (Doc 07 §10). Until the client accepts the
        # Stage 1 price; a change while it is being priced makes a fresh quote.
        def update_plan
          unless @engagement.plan_open_to_mjadi?
            return render json: { error: "The plan is fixed once the client has agreed the Stage 1 price" }, status: :conflict
          end

          planned = Engagements::PlannedDepartments.normalise(params.permit(departments: %i[name count]).fetch(:departments, []))
          return render json: { error: "Choose at least one department" }, status: :unprocessable_entity if planned.empty?

          @engagement.update!(planned_departments: planned)
          KeyPerson::Completion.hand_over_to_pricing(@engagement, actor: current_consultant_user)
          Pricing::ProposeStage1.reprice_if_pricing(@engagement, actor: current_consultant_user, reason: "Plan changed")
          render json: KeyPerson::ConsultantView.new(@engagement.reload).json
        end

        private

        def set_engagement
          company = ::Company.find(params[:company_id])
          raise ActiveRecord::RecordNotFound unless assigned_company_ids.include?(company.id)

          @engagement = company.current_engagement or raise ActiveRecord::RecordNotFound
        end

        def set_participant
          @participant = @engagement.participants.key_persons.find(params[:participant_id])
        end
      end
    end
  end
end
