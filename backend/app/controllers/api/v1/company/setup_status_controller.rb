# frozen_string_literal: true

module Api
  module V1
    module Company
      class SetupStatusController < BaseController
        skip_before_action :require_active_subscription!

        def show
          authorize current_company, :show?
          completeness = Companies::ProfileCompleteness.call(company: current_company)
          docs_count = current_company.documents.where(source: "company_portal_upload").count

          render json: {
            display_name: current_company.display_name || current_company.name,
            onboarding_complete: current_company.onboarding_complete?,
            profile_completeness_percent: completeness[:completeness_percent],
            required_sections_complete: completeness[:required_sections_complete],
            missing_required_sections: completeness[:missing_required_sections],
            employees_invited: current_company.invited_count,
            employees_completed: current_company.completed_count,
            documents_count: docs_count,
            next_actions: next_actions(completeness, docs_count)
          }
        end

        private

        def next_actions(completeness, docs_count)
          actions = []
          if current_company.invited_count.zero?
            actions << { key: "invite_employees", label: "Invite employees", path: "/company/employees", priority: 1 }
          end
          if docs_count.zero?
            actions << { key: "upload_documents", label: "Upload context documents", path: "/company/documents", priority: 2 }
          end
          unless completeness[:required_sections_complete]
            actions << {
              key: "finish_profile_setup",
              label: "Finish company profile setup",
              path: "/company/profile?tab=review",
              priority: 0
            }
          elsif completeness[:completeness_percent] < 100
            actions << {
              key: "complete_profile",
              label: "Complete optional profile sections",
              path: "/company/profile",
              priority: 3
            }
          end
          actions.sort_by { |a| a[:priority] }
        end
      end
    end
  end
end
