# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # Synthesis for a company the consultant is assigned to (Doc 10 §17): what
      # it grouped and concluded, a "run again", and the consultant's decisions
      # on it. Every decision needs a reason and acts on the current version.
      class SynthesisController < BaseController
        before_action :set_engagement

        def show
          render json: Synthesis::ConsultantView.new(@engagement).json
        end

        def run
          SynthesisRunJob.request(@engagement, trigger: "MANUAL", wait: 0)
          render json: Synthesis::ConsultantView.new(@engagement).json, status: :accepted
        end

        def decide
          Synthesis::Decide.call(
            engagement: @engagement, actor: current_consultant_user, action: params.require(:decision_action),
            subject_id: params[:subject_id], rationale: params[:rationale],
            params: params.fetch(:details, {}).permit!.to_h
          )
          render json: Synthesis::ConsultantView.new(@engagement).json
        rescue Synthesis::Decide::Error => e
          render json: { error: e.message }, status: e.status
        end

        private

        def set_engagement
          company = ::Company.find(params[:company_id])
          raise ActiveRecord::RecordNotFound unless assigned_company_ids.include?(company.id)

          @engagement = company.current_engagement or raise ActiveRecord::RecordNotFound
        end
      end
    end
  end
end
