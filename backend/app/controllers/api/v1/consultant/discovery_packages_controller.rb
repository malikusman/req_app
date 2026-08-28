# frozen_string_literal: true

module Api
  module V1
    module Consultant
      # The consultant amends the Discovery handover, and states what else they need
      # to know. They never write question text — `create_requirement` takes their
      # words and the agent drafts from them.
      class DiscoveryPackagesController < BaseController
        include Api::V1::DiscoveryPackageJson

        before_action :load_package

        # Edit the recommendation the agent produced. The original stays in
        # agent_payload, so an edit is never destructive.
        def update
          @package.update!(package_params)
          render json: { discovery_package: discovery_package_json(@package.reload) }
        end

        # A consultant's own issue or solution.
        def create_item
          item = @package.discovery_package_items.create!(
            item_params.merge(origin: "consultant", status: "accepted")
          )
          render json: { item: package_item_json(item) }, status: :created
        end

        # Accept, amend or reject an item. An agent item is never deleted — a
        # rejection is a signal about agent quality and is carried forward.
        def update_item
          item = @package.discovery_package_items.find(params[:id])
          item.update!(item_params)
          render json: { item: package_item_json(item.reload) }
        end

        def create_requirement
          requirement = ConsultantRequirements::CreateService.call(
            package: @package,
            consultant: current_consultant_user,
            # Read rather than require: Rails' `require` treats a whitespace-only
            # value as missing and raises a bare 400, where the consultant should
            # see why their submission was rejected.
            statement: params[:statement]
          )
          render json: { requirement: requirement_json(requirement) }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # The consultant is the authority on whether their own need is met, so they
        # can close it by hand whatever the agent judged.
        def update_requirement
          requirement = @package.consultant_requirements.find(params[:id])

          case params[:status]
          when "satisfied"
            requirement.satisfy!(basis: "consultant_manual")
          when "withdrawn"
            requirement.update!(status: "withdrawn")
            # Drafts for a withdrawn need must not stay in the queue.
            requirement.discovery_followup_questions.pending.update_all(
              status: "superseded", updated_at: Time.current
            )
          else
            return render json: { error: "Unsupported status" }, status: :unprocessable_entity
          end

          render json: { requirement: requirement_json(requirement.reload) }
        end

        # Reorder or skip a drafted question. Not rewrite it.
        def update_question
          question = @package.discovery_followup_questions.find(params[:id])
          unless question.status.in?(%w[drafted queued])
            return render json: { error: "This question has already been sent" },
                          status: :unprocessable_entity
          end

          question.update!(question_params)
          render json: { question: followup_question_json(question.reload) }
        end

        def send_question
          question = @package.discovery_followup_questions.find(params[:id])
          ConsultantRequirements::SendQuestionService.call(
            question: question,
            consultant: current_consultant_user,
            # Omitted means the employee's own preferred channel decides.
            channel: params[:channel]
          )
          render json: { question: followup_question_json(question.reload) }
        rescue ConsultantRequirements::SendQuestionService::BudgetExhausted,
               ConsultantFollowup::SendService::Undeliverable => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def load_package
          @package = policy_scope(DiscoveryPackage).find(params[:package_id])
          authorize @package, :update?
        end

        def package_params
          params.permit(:recommendation, :recommendation_rationale)
        end

        def item_params
          permitted = params.permit(:kind, :title, :body, :impact, :status, :linked_item_id, :ordinal)
          # Editing an agent item's text marks it amended, so the package shows what
          # the consultant changed. An explicit status always wins — otherwise
          # rejecting an item while also editing it would record it as amended.
          if action_name == "update_item" && permitted[:status].blank? && permitted[:body].present?
            permitted[:status] = "amended"
          end
          permitted
        end

        def question_params
          params.permit(:queue_position, :status).tap do |permitted|
            allowed = %w[drafted queued skipped]
            permitted.delete(:status) unless allowed.include?(permitted[:status])
          end
        end
      end
    end
  end
end
