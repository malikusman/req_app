# frozen_string_literal: true

module Api
  module V1
    module Platform
      class MonitoringController < BaseController
        def show
          render json: {
            companies: company_metrics,
            subscriptions: subscription_metrics,
            discovery: discovery_metrics,
            multimodal: multimodal_metrics,
            reports: report_metrics,
            impersonations: impersonation_metrics
          }
        end

        private

        def company_metrics
          {
            total: ::Company.count,
            onboarded: ::Company.where.not(portal_onboarding_completed_at: nil).count,
            avg_readiness: ::Company.average(:report_readiness_score).to_f.round(1)
          }
        end

        def subscription_metrics
          grouped = Subscription.group(:status).count
          {
            by_status: grouped,
            trials_expiring_7d: Subscription.where(status: "trial")
              .where("trial_ends_at <= ?", 7.days.from_now).count,
            at_conversation_limit: companies_at_limit
          }
        end

        def companies_at_limit
          count = 0
          Subscription.includes(:company).find_each do |sub|
            enforcer = Subscriptions::ConversationLimitEnforcer.new(company: sub.company)
            count += 1 if enforcer.limit_reached?
          end
          count
        end

        def discovery_metrics
          {
            active_conversations: Conversation.where(status: %w[onboarding discovery]).count,
            completed_employees: Employee.where(participation_status: "completed").count,
            conversations_last_24h: Conversation.where("created_at >= ?", 24.hours.ago).count
          }
        end

        def multimodal_metrics
          {
            ready_attachments: MediaAttachment.where(status: "ready").count,
            processing_attachments: MediaAttachment.where(status: "processing").count,
            failed_attachments: MediaAttachment.where(status: "failed").count,
            attachments_last_24h: MediaAttachment.where("created_at >= ?", 24.hours.ago).count,
            companies_with_multimodal_enabled: ::Company.where("settings ->> 'discovery_multimodal_enabled' = 'true'").count,
            companies_with_media_indexing_enabled: ::Company.where("settings ->> 'discovery_media_indexing_enabled' = 'true'").count
          }
        end

        def report_metrics
          {
            ready: Report.where(status: "ready").count,
            generating: Report.where(status: %w[queued generating]).count,
            failed: Report.where(status: "failed").count
          }
        end

        def impersonation_metrics
          {
            active_sessions: ImpersonationSession.active.count,
            last_24h: ImpersonationSession.where("created_at >= ?", 24.hours.ago).count
          }
        end
      end
    end
  end
end
