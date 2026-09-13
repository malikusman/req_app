# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # Questions worth asking this employee, proposed with a reason.
      #
      # GET is deliberately free of side effects: nothing is persisted and no budget
      # is spent, so a consultant can look without committing. POST is the moment a
      # suggestion becomes a real requirement.
      class DeepDiveSuggestionsController < BaseController
        before_action :load_package

        def index
          authorize @package, :show?

          render json: ConsultantDeepDive::SuggestService.call(package: @package)
        end

        def create
          authorize @package, :show?

          result = ConsultantDeepDive::AcceptService.call(
            package: @package,
            consultant: current_consultant_user,
            body: params[:body],
            rationale: params[:rationale]
          )

          render json: {
            requirement_id: result[:requirement].id,
            question: {
              id: result[:question].id,
              body: result[:question].body,
              rationale: result[:question].rationale,
              status: result[:question].status
            }
          }, status: :created
        rescue ConsultantDeepDive::AcceptService::BudgetExhausted => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        # policy_scope, not a bare find: it is what confines a consultant to the
        # companies they are actually assigned to, and this controller is reached
        # with a package id straight off the URL.
        def load_package
          @package = policy_scope(DiscoveryPackage).find(params[:discovery_package_id])
        end
      end
    end
  end
end
