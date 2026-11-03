# frozen_string_literal: true

module Api
  module V1
    module Company
      # Participant planning (Doc 07 §7): the people the key user names to take part
      # (P3) and the other managers Mjadi should speak with (P4). Both are optional;
      # nobody here is invited yet. Staff are invited from the Employees page, and
      # managers when the conversations with leadership begin.
      class OnboardingParticipantsController < BaseController
        def index
          authorize :onboarding, :show?
          render json: { participants: scope.order(:created_at).map { |p| participant_json(p) } }
        end

        def create
          authorize :onboarding, :update_profile?
          engagement = current_company.current_engagement
          return render json: { errors: ["There is no engagement to plan"] }, status: :unprocessable_entity unless engagement

          participant = engagement.participants.new(participant_params.merge(company: current_company))
          save(participant, status: :created)
        end

        def update
          authorize :onboarding, :update_profile?
          participant = scope.find(params[:id])
          participant.assign_attributes(participant_params.except(:participant_type))
          save(participant, status: :ok)
        end

        # Someone already invited stays an employee; they just leave the plan.
        def destroy
          authorize :onboarding, :update_profile?
          scope.find(params[:id]).destroy!
          head :no_content
        end

        private

        def scope
          engagement = current_company.current_engagement
          engagement ? engagement.participants : EngagementParticipant.none
        end

        def save(participant, status:)
          if participant.save
            render json: { participant: participant_json(participant), warnings: warnings_for(participant) }, status: status
          else
            render json: { errors: participant.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def participant_params
          attrs = params.require(:participant)
                        .permit(:participant_type, :name, :role_title, :department, :scope, :email, :phone_e164,
                                :preferred_language)
                        .to_h.symbolize_keys
          attrs[:phone_e164] = attrs[:phone_e164].present? ? PhoneNormalizer.call(attrs[:phone_e164]) : nil if attrs.key?(:phone_e164)
          attrs[:email] = attrs[:email].to_s.strip.downcase.presence if attrs.key?(:email)
          attrs[:participant_type] = attrs[:participant_type].to_s.upcase if attrs.key?(:participant_type)
          attrs
        end

        # A phone number belongs to one employee record across all clients, so a
        # person already taking part elsewhere can't be invited here with it.
        def warnings_for(participant)
          return [] if participant.phone_e164.blank?

          taken = Employee.where(phone_e164: participant.phone_e164).where.not(company_id: current_company.id).exists?
          taken ? ["This phone number is already in use by another company's participant, so an invitation to it won't go through."] : []
        end

        def participant_json(participant)
          participant.slice(:id, :participant_type, :name, :role_title, :department, :scope, :email, :phone_e164,
                            :preferred_language, :nominated_by_client, :added_after_pricing, :employee_id)
        end
      end
    end
  end
end
