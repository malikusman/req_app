# frozen_string_literal: true

module Dashboard
  class PlatformSummary
    def self.call
      new.call
    end

    # Shared so the Approvals worklist endpoint and the dashboard triage row
    # render the same queue.
    def self.reports_awaiting
      new.reports_awaiting_payload
    end

    def call
      {
        monitoring: monitoring_payload,
        system: system_payload,
        trials_expiring_soon: trials_payload,
        reports_awaiting_approval: reports_awaiting_payload
      }
    end

    def reports_awaiting_payload
      @reports_awaiting_payload ||= build_reports_awaiting_payload
    end

    def build_reports_awaiting_payload
      # Only the latest awaiting version per company — a superseded version left
      # un-approved shouldn't clutter the queue.
      latest = Report.awaiting_platform_approval
                     .includes(:company)
                     .group_by(&:company_id)
                     .map { |_, reports| reports.max_by(&:version) }

      latest.sort_by { |r| r.generated_at || Time.at(0) }.reverse.map do |report|
        company = report.company
        {
          report: { id: report.id, version: report.version, generated_at: report.generated_at },
          company: { id: company.id, name: company.display_name || company.name },
          has_reviewer: company.reviewer_assignments.active.exists?,
          blocked_needs_info: report.report_reviews.where(status: "needs_info").exists?
        }
      end
    end

    private

    def monitoring_payload
      grouped = Subscription.group(:status).count
      {
        companies: {
          total: Company.count,
          onboarded: Company.where.not(portal_onboarding_completed_at: nil).count,
          avg_readiness: Company.average(:report_readiness_score).to_f.round(1)
        },
        subscriptions: {
          by_status: grouped,
          active_trials: grouped["trial"].to_i,
          trials_expiring_7d: Subscription.where(status: "trial")
            .where("trial_ends_at <= ?", 7.days.from_now).count,
          at_conversation_limit: companies_at_limit
        },
        discovery: {
          active_conversations: Conversation.where(status: %w[onboarding discovery]).count,
          completed_employees: Employee.where(participation_status: "completed").count,
          conversations_last_24h: Conversation.where("created_at >= ?", 24.hours.ago).count
        },
        multimodal: {
          ready_attachments: MediaAttachment.where(status: "ready").count,
          processing_attachments: MediaAttachment.where(status: "processing").count,
          failed_attachments: MediaAttachment.where(status: "failed").count,
          attachments_last_24h: MediaAttachment.where("created_at >= ?", 24.hours.ago).count,
          companies_with_multimodal_enabled: Company.where("settings ->> 'discovery_multimodal_enabled' = 'true'").count,
          companies_with_media_indexing_enabled: Company.where("settings ->> 'discovery_media_indexing_enabled' = 'true'").count
        },
        reports: {
          ready: Report.where(status: "ready").count,
          # The actionable queue is deduped to the latest awaiting version per
          # company — the stat must match the queue / nav badge, not the raw scope.
          awaiting_approval: reports_awaiting_payload.size,
          generating: Report.where(status: %w[queued generating]).count,
          failed: Report.where(status: "failed").count
        },
        impersonations: {
          active_sessions: ImpersonationSession.active.count,
          last_24h: ImpersonationSession.where("created_at >= ?", 24.hours.ago).count
        }
      }
    end

    def system_payload
      {
        services: {
          langgraph: check_langgraph,
          gotenberg: check_gotenberg,
          redis: check_redis,
          openai: check_openai
        },
        whatsapp_delivery: whatsapp_health
      }
    end

    def trials_payload
      Company.joins(:subscription)
             .includes(:subscription)
             .where(subscriptions: { status: "trial" })
             .where("subscriptions.trial_ends_at <= ?", 7.days.from_now)
             .order("subscriptions.trial_ends_at ASC")
             .map do |company|
        {
          company: {
            id: company.id,
            name: company.display_name || company.name,
            report_readiness_score: company.report_readiness_score,
            completed_count: company.completed_count,
            invited_count: company.invited_count
          },
          subscription: {
            plan: company.subscription.plan,
            trial_ends_at: company.subscription.trial_ends_at,
            days_remaining: [((company.subscription.trial_ends_at - Time.current) / 1.day).ceil, 0].max
          }
        }
      end
    end

    def companies_at_limit
      count = 0
      Subscription.includes(:company).find_each do |sub|
        enforcer = Subscriptions::ConversationLimitEnforcer.new(company: sub.company)
        count += 1 if enforcer.limit_reached?
      end
      count
    end

    def check_langgraph
      uri = URI("#{ENV.fetch('LANGGRAPH_URL', 'http://langgraph:8000')}/health")
      response = Net::HTTP.get_response(uri)
      { status: response.is_a?(Net::HTTPSuccess) ? "ok" : "error" }
    rescue StandardError => e
      { status: "error", detail: e.message }
    end

    def check_gotenberg
      uri = URI("#{ENV.fetch('GOTENBERG_URL', 'http://gotenberg:3000')}/health")
      response = Net::HTTP.get_response(uri)
      { status: response.is_a?(Net::HTTPSuccess) ? "ok" : "error" }
    rescue StandardError => e
      { status: "unavailable", detail: e.message }
    end

    def check_redis
      REDIS.ping
      { status: "ok" }
    rescue StandardError => e
      { status: "error", detail: e.message }
    end

    def check_openai
      if ENV["OPENAI_API_KEY"].present?
        { status: "configured" }
      else
        { status: "unconfigured" }
      end
    end

    def whatsapp_health
      since = 24.hours.ago
      metrics = WhatsappDeliveryMetric.where("hour_bucket >= ?", since).group(:metric_type).sum(:count)
      sent = metrics["template_sent"].to_i
      failed = metrics["template_failed"].to_i + metrics["api_error"].to_i

      {
        template_sent: sent,
        template_failed: failed,
        failure_rate: sent.zero? ? 0.0 : (failed.to_f / (sent + failed) * 100).round(1)
      }
    end
  end
end
