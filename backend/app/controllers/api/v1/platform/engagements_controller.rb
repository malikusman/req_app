# frozen_string_literal: true

module Api
  module V1
    module Platform
      # Engagement set-up by Mjadi (Doc 07 §3). The only way a client company comes
      # into being: there is no public self-sign-up and no trial.
      class EngagementsController < BaseController
        def create
          authorize ::Company, :create?
          engagement = Engagements::Create.call(platform_user: current_platform_user, params: engagement_params,
                                                request: request)
          render json: { engagement: self.class.engagement_json(engagement) }, status: :created
        rescue Engagements::Create::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # S2–S8 may be corrected while the client is still setting up. The scope and
        # departments are fixed once onboarding has been handed over.
        def update
          engagement = find_engagement
          attrs = engagement_params.slice(:proposal_reference, :languages, :scope_type, :departments_in_scope).to_h
          if attrs.key?("languages")
            attrs["languages"] = Array(attrs["languages"]).map { |l| l.to_s.downcase }.grep(Engagements::Create::LANGUAGE_FORMAT)
          end
          if engagement_params.key?(:lead_consultant_id)
            attrs["lead_consultant"] = ConsultantUser.find_by(id: engagement_params[:lead_consultant_id], status: "active")
          end
          unless %w[SET_UP ONBOARDING].include?(engagement.status)
            attrs = attrs.except("scope_type", "departments_in_scope")
          end
          # Counts the client couldn't give, settled with them by Mjadi before
          # pricing (Doc 07 §10). Only until the engagement is priced.
          if engagement_params.key?(:planned_departments) && engagement.status == "KEY_PERSON_DISCOVERY"
            attrs["planned_departments"] = Engagements::PlannedDepartments.normalise(engagement_params[:planned_departments])
          end
          engagement.update!(attrs)
          KeyPerson::Completion.hand_over_to_pricing(engagement, actor: current_platform_user) if attrs.key?("planned_departments")
          PlatformAuditService.log!(platform_user: current_platform_user, action: "engagement_updated",
                                    target: engagement, metadata: { fields: attrs.keys }, request: request)
          render json: { engagement: self.class.engagement_json(engagement) }
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end

        def resend_invitation
          engagement = find_engagement
          key_user = engagement.key_user
          unless key_user&.status == "pending"
            return render json: { error: "The key user has already set their password" }, status: :unprocessable_entity
          end

          Engagements::Invite.call(engagement: engagement)
          PlatformAuditService.log!(platform_user: current_platform_user, action: "engagement_invitation_resent",
                                    target: engagement, request: request)
          render json: { ok: true, email: key_user.email }
        end

        # Reads the client's website again for pre-fill proposals. A read still under
        # way is not started twice; one stuck for longer than the job's retry window
        # can be.
        def reread_website
          engagement = find_engagement
          if engagement.company.website_url.blank?
            return render json: { error: "The company has no website" }, status: :unprocessable_entity
          end
          if reading?(engagement)
            return render json: { error: "The website is already being read" }, status: :conflict
          end

          WebsitePrefillJob.start(engagement)
          PlatformAuditService.log!(platform_user: current_platform_user, action: "engagement_website_reread",
                                    target: engagement, request: request)
          render json: { engagement: self.class.engagement_json(engagement.reload) }
        end

        def self.engagement_json(engagement)
          key_user = engagement.key_user
          {
            id: engagement.id,
            company_id: engagement.company_id,
            status: engagement.status,
            status_history: engagement.status_history,
            scope_type: engagement.scope_type,
            departments_in_scope: engagement.departments_in_scope,
            languages: engagement.languages,
            proposal_reference: engagement.proposal_reference,
            planned_departments: engagement.planned_departments,
            planned_participant_count: engagement.planned_participant_count,
            onboarding_submitted_at: engagement.onboarding_submitted_at,
            prefill_status: engagement.prefill_status,
            prefill_entity_note: engagement.prefill_entity_note,
            prefill_candidates: engagement.prefill_candidates.order(:id).map { |c|
              c.slice(:id, :target_field, :value, :display_text, :confidence, :status, :source_url, :evidence_excerpt)
            },
            confidentiality_acknowledged_at: engagement.confidentiality_acknowledged_at,
            # How far each conversation with leadership has got — never what was said.
            leadership: engagement.participants.key_persons.order(:created_at).map { |p|
              session = p.conversation_sessions.last
              { name: p.name, key_user: p.key_user?, participation_status: p.participation_status,
                close_reason: session&.close_reason, needs_review: session&.needs_review || false }
            },
            key_user: key_user && { id: key_user.id, name: key_user.name, email: key_user.email,
                                    phone: key_user.phone, job_title: key_user.job_title, status: key_user.status },
            lead_consultant: engagement.lead_consultant && { id: engagement.lead_consultant.id,
                                                             name: engagement.lead_consultant.name },
            created_at: engagement.created_at
          }
        end

        private

        READ_STUCK_AFTER = 15.minutes

        def reading?(engagement)
          %w[pending running].include?(engagement.prefill_status) && engagement.updated_at > READ_STUCK_AFTER.ago
        end

        def find_engagement
          engagement = Engagement.find(params[:id])
          authorize engagement.company, :update?
          engagement
        end

        def engagement_params
          params.require(:engagement).permit(
            :company_name, :website_url, :scope_type, :lead_consultant_id, :proposal_reference,
            departments_in_scope: [], languages: [], planned_departments: %i[name count],
            key_user: %i[name role_title email phone]
          )
        end
      end
    end
  end
end
