# frozen_string_literal: true

module Api
  module V1
    module Platform
      class PlaybooksController < BaseController
        def index
          playbooks = DiscoveryPlaybook.order(department: :asc, version: :desc)
          render json: { playbooks: playbooks.map { |p| playbook_json(p) } }
        end

        def show
          playbook = DiscoveryPlaybook.find(params[:id])
          render json: { playbook: playbook_json(playbook) }
        end

        def create
          playbook = DiscoveryPlaybook.new(playbook_params)
          playbook.created_by_platform_user = current_platform_user
          playbook.version = next_version(playbook.department)
          playbook.save!

          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "playbook_created",
            target: playbook,
            metadata: { department: playbook.department, version: playbook.version },
            request: request
          )

          render json: { playbook: playbook_json(playbook) }, status: :created
        end

        def update
          playbook = DiscoveryPlaybook.find(params[:id])
          playbook.update!(playbook_params)

          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "playbook_updated",
            target: playbook,
            request: request
          )

          render json: { playbook: playbook_json(playbook) }
        end

        def activate
          playbook = DiscoveryPlaybook.find(params[:id])

          ActiveRecord::Base.transaction do
            DiscoveryPlaybook.where(department: playbook.department).update_all(active: false)
            playbook.update!(active: true, activated_at: Time.current)
          end

          PlatformAuditService.log!(
            platform_user: current_platform_user,
            action: "playbook_activated",
            target: playbook,
            metadata: { department: playbook.department, version: playbook.version },
            request: request
          )

          render json: { playbook: playbook_json(playbook.reload) }
        end

        private

        def playbook_params
          params.require(:playbook).permit(:department, :prompt_block, :notes)
        end

        def next_version(department)
          (DiscoveryPlaybook.where(department: department).maximum(:version) || 0) + 1
        end

        def playbook_json(playbook)
          {
            id: playbook.id,
            department: playbook.department,
            version: playbook.version,
            prompt_block: playbook.prompt_block,
            active: playbook.active,
            notes: playbook.notes,
            activated_at: playbook.activated_at,
            created_at: playbook.created_at,
            updated_at: playbook.updated_at
          }
        end
      end
    end
  end
end
