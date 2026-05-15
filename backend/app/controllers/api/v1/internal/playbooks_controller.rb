# frozen_string_literal: true

module Api
  module V1
    module Internal
      class PlaybooksController < ApplicationController
        include InternalAuthenticatable

        def active
          department = params[:department].presence || "default"
          playbook = DiscoveryPlaybook.active_playbook_for(department)

          if playbook
            render json: playbook_json(playbook)
          else
            render json: { error: "not_found" }, status: :not_found
          end
        end

        private

        def playbook_json(playbook)
          {
            department: playbook.department,
            version: playbook.version,
            prompt_block: playbook.prompt_block,
            active: playbook.active
          }
        end
      end
    end
  end
end
