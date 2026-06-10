# frozen_string_literal: true

module Api
  module V1
    module Platform
      class AuditLogsController < BaseController
        PER_PAGE = 50

        def index
          logs = PlatformAuditLog.includes(:platform_user).order(created_at: :desc)

          logs = logs.where(action: params[:action]) if params[:action].present?
          if params[:company_id].present?
            company_id = params[:company_id].to_i
            logs = logs.where(
              "(target_type = ? AND target_id = ?) OR metadata @> ?",
              "Company",
              company_id,
              { "company_id" => company_id }.to_json
            )
          end

          page = [params[:page].to_i, 1].max
          total = logs.count
          records = logs.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

          render json: {
            audit_logs: records.map { |log| audit_log_json(log) },
            pagination: { page: page, per_page: PER_PAGE, total: total }
          }
        end

        private

        def audit_log_json(log)
          {
            id: log.id,
            actor: log.platform_user.email,
            action: log.action,
            target: target_label(log),
            target_type: log.target_type,
            target_id: log.target_id,
            metadata: log.metadata,
            created_at: log.created_at,
            ip: log.ip_address
          }
        end

        def target_label(log)
          return metadata_target(log) if log.target_type.blank?

          target = log.target_type.safe_constantize&.find_by(id: log.target_id)
          case log.target_type
          when "Company"
            target&.display_name || target&.name || "Company ##{log.target_id}"
          when "Report"
            company = target&.company
            company_name = company&.display_name || company&.name || "Company"
            "Report v#{target&.version} — #{company_name}"
          when "PlatformUser", "ReviewerUser", "CompanyUser"
            target&.email || "#{log.target_type} ##{log.target_id}"
          when "DiscoveryPlaybook"
            target ? "Playbook #{target.department} v#{target.version}" : "Playbook ##{log.target_id}"
          else
            "#{log.target_type} ##{log.target_id}"
          end
        rescue StandardError
          "#{log.target_type} ##{log.target_id}"
        end

        def metadata_target(log)
          log.metadata["target_label"] || log.metadata["company_name"] || "—"
        end
      end
    end
  end
end
