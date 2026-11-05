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
        # Onboarding is one short form, submitted or not; there is no percentage.
        onboarding_submitted_at: @company.current_engagement&.onboarding_submitted_at,
        engagement_status: @company.current_engagement&.status,
        planned_participant_count: @company.current_engagement&.planned_participant_count,
        leadership: leadership_json,
        usage: enforcer.usage_summary,
        latest_report: latest_report_json(latest_report),
        opportunity_estimate: opportunity_estimate_json,
        employees_summary: employees_summary,
        intel_counts: intel_counts,
        integrations: integrations_status,
        impersonating: @impersonating,
        impersonation_expires_at: @impersonation_session&.expires_at
      }
    end

    private

    # The conversations with leadership as the client sees them: the key user's
    # own, and each other manager's status — never what anyone said (Doc 14 §9.2).
    def leadership_json
      engagement = @company.current_engagement
      return nil unless engagement

      own = engagement.participants.find_by(source: "KEY_USER")
      managers = engagement.participants.planned.key_persons.order(:created_at)
      return nil if own.nil? && managers.none?

      session = own&.conversation_sessions&.last
      {
        available: KeyPerson::Conversation.available?,
        is_key_user: engagement.key_user_id == @company_user.id,
        own: own && { participation_status: own.participation_status, finished: session&.finished? || false },
        managers: managers.map do |m|
          { id: m.id, name: m.name, role_title: m.role_title, participation_status: m.participation_status,
            can_invite: m.email.present?, reminders_used_up: m.reminder_count >= KeyPerson::Reminders::NOT_STARTED_AFTER.size }
        end
      }
    end

    # The consultant's opportunity estimate — surfaced only from a report that has
    # actually shipped to the company (never leaked pre-approval), newest first.
    def opportunity_estimate_json
      review = ReportReview
               .joins(:report)
               .includes(:consultant_user)
               .where(reports: { company_id: @company.id, visibility: "shared_with_company" })
               .where.not(opportunity_amount: nil)
               .order(Arel.sql("reports.version DESC, report_reviews.updated_at DESC"))
               .first
      return nil unless review

      {
        amount: review.opportunity_amount,
        unit: review.opportunity_unit,
        basis: review.opportunity_basis,
        consultant_name: review.consultant_user&.name,
        report_version: review.report.version
      }
    end

    def intel_counts
      docs = @company.documents.not_leadership.where(purged_at: nil)
      snapshot = @company.intelligence_snapshot.is_a?(Hash) ? @company.intelligence_snapshot : {}

      {
        total_documents: docs.count,
        ready_documents: docs.ready.count,
        # Uploaded and still being worked on — what "we're analyzing your
        # documents" means. A failed upload is not "in progress".
        processing_documents: docs.where(status: %w[uploaded pending processing]).count,
        open_clarifications: @company.company_clarification_questions.open_for_admin.count,
        signal_count: (snapshot["signal_count"].presence || Array(snapshot["top_pain_points"]).size).to_i,
        pattern_count: Array(snapshot["emerging_patterns"]).size,
        recommendation_count: snapshot["recommendation_count"].to_i,
        systems_count: @company.company_systems.count
      }
    end

    def integrations_status
      {
        openai_configured: ENV["OPENAI_API_KEY"].present?,
        stripe_configured: ENV["STRIPE_SECRET_KEY"].present?,
        gotenberg_ok: gotenberg_healthy?,
        mocks_allowed: MocksAllowed.allowed?,
        billing_visible: @company.merged_settings["client_billing_visible"] == true
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
