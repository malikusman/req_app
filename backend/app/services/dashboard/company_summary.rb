# frozen_string_literal: true

require "net/http"

module Dashboard
  class CompanySummary
    def self.call(company:, company_user:, impersonating: false, impersonation_session: nil)
      new(
        company: company,
        company_user: company_user,
        impersonating: impersonating,
        impersonation_session: impersonation_session
      ).call
    end

    def initialize(company:, company_user:, impersonating:, impersonation_session:)
      @company = company
      @company_user = company_user
      @impersonating = impersonating
      @impersonation_session = impersonation_session
    end

    def call
      ensure_snapshot!
      latest_report = @company.reports.order(version: :desc).first
      enforcer = Subscriptions::ConversationLimitEnforcer.new(company: @company)

      {
        user: {
          id: @company_user.id,
          email: @company_user.email,
          name: @company_user.name,
          role: @company_user.role,
          onboarding_completed_at: @company_user.onboarding_completed_at
        },
        company: company_json,
        snapshot: @company.intelligence_snapshot,
        report_readiness_score: @company.report_readiness_score,
        report_readiness_breakdown: @company.report_readiness_breakdown,
        engagement_mode: @company.engagement_mode,
        docs_first_phase: @company.docs_first_phase?,
        questionnaire_completed_at: @company.questionnaire_completed_at,
        questionnaire_completion_percent: Companies::QuestionnaireProgress.call(@company.questionnaire_answers)[:completion_percent],
        usage: enforcer.usage_summary,
        latest_report: latest_report_json(latest_report),
        employees_summary: employees_summary,
        integrations: integrations_status,
        impersonating: @impersonating,
        impersonation_expires_at: @impersonation_session&.expires_at
      }
    end

    private

    def integrations_status
      {
        openai_configured: ENV["OPENAI_API_KEY"].present?,
        stripe_configured: ENV["STRIPE_SECRET_KEY"].present?,
        gotenberg_ok: gotenberg_healthy?,
        mocks_allowed: MocksAllowed.allowed?
      }
    end

    def gotenberg_healthy?
      uri = URI("#{ENV.fetch('GOTENBERG_URL', 'http://gotenberg:3000')}/health")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 2
      http.read_timeout = 2
      response = http.request(Net::HTTP::Get.new(uri))
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def ensure_snapshot!
      return if @company.intelligence_snapshot.present?

      @company.update!(intelligence_snapshot: Intelligence::SnapshotBuilder.call(company: @company))
      @company.reload
    end

    def company_json
      {
        id: @company.id,
        name: @company.name,
        display_name: @company.display_name,
        locale: @company.locale,
        portal_onboarding_completed_at: @company.portal_onboarding_completed_at,
        report_readiness_score: @company.report_readiness_score,
        completed_count: @company.completed_count,
        invited_count: @company.invited_count,
        onboarding_complete: @company.onboarding_complete?,
        engagement_mode: @company.engagement_mode,
        docs_first_phase: @company.docs_first_phase?
      }
    end

    def latest_report_json(report)
      return nil unless report

      {
        id: report.id,
        version: report.version,
        status: report.status,
        visibility: report.visibility,
        generated_at: report.generated_at
      }
    end

    def employees_summary
      started = @company.employees.where(participation_status: "started")
      stalled = started.stalled
      can_nudge = started.select { |employee| Employees::NudgeEligibility.can_nudge?(employee) }

      {
        stalled_count: stalled.count,
        in_progress_count: started.count,
        can_nudge_count: can_nudge.size,
        stalled_employees: stalled.limit(5).map { |employee| stalled_employee_json(employee) }
      }
    end

    def stalled_employee_json(employee)
      {
        id: employee.id,
        display_name: employee.display_name,
        department: employee.department,
        last_active_at: employee.last_active_at,
        can_nudge: Employees::NudgeEligibility.can_nudge?(employee)
      }
    end
  end
end
