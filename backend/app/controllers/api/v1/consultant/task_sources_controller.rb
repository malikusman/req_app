# frozen_string_literal: true

module Api
  module V1
    module Consultant
      class TaskSourcesController < BaseController
        PAGE_SIZE = 100

        def index
          company = policy_scope(::Company).find(params[:company_id])
          scope = policy_scope(::TaskSource).where(company: company)
          scope = scope.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
          sources = scope.where("task_sources.id > ?", params[:after_id].to_s.to_i).order(:id).limit(PAGE_SIZE + 1).to_a
          page = sources.first(PAGE_SIZE)
          message_ids = page.flat_map { |source| source.evidence_references.pluck("message_id") }.compact
          evidence_conversations = TaskSource.evidence_messages.where(id: message_ids).pluck(:id, :conversation_id).to_h

          render json: {
            task_sources: page.map { |source| source_json(source, evidence_conversations) },
            next_after_id: sources.size > PAGE_SIZE ? page.last.id : nil
          }
        end

        private

        def source_json(source, evidence_conversations)
          # The snapshot includes quotes, corrections and other extracted text.
          # Return only source metadata and authorized reference IDs.
          references = source.evidence_references.filter_map do |reference|
            id = reference["message_id"]
            next if id && evidence_conversations[id] != source.conversation_id

            reference.slice("message_id", "turn")
          end
          source.as_json(only: %i[id company_id employee_id conversation_id finding_id source_kind
                                  local_task_id name description discovery_revision version created_at])
                .merge(evidence_references: references)
        end
      end
    end
  end
end
