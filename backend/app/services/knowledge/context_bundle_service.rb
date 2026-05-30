# frozen_string_literal: true

module Knowledge
  class ContextBundleService
    INFO_REQUEST_LIMIT = 15
    REVIEWER_FEEDBACK_LIMIT = 20
    DOCUMENT_LIMIT = 30

    def self.call(company:, department: nil)
      new(company: company, department: department).call
    end

    def initialize(company:, department: nil)
      @company = company
      @department = department.presence
      @context = (company.profile_context || {}).deep_stringify_keys
    end

    def call
      {
        company_id: @company.id,
        profile_text: Companies::ProfileSummary.for_ai(company: @company),
        profile_completeness: Companies::ProfileCompleteness.call(company: @company),
        gaps_constraints: @context["gaps_constraints"] || {},
        info_requests: info_requests_payload,
        reviewer_feedback: reviewer_feedback_payload,
        employee_profile_aggregate: employee_profile_aggregate,
        document_inventory: document_inventory_payload
      }
    end

    private

    def info_requests_payload
      requests = @company.company_info_requests
                         .includes(:company_info_request_replies)
                         .where(status: %w[open answered])
                         .order(updated_at: :desc)
                         .limit(INFO_REQUEST_LIMIT)

      requests.map do |req|
        latest_reply = req.company_info_request_replies.order(:created_at).last
        {
          id: req.id,
          subject: req.subject,
          body: req.body.truncate(500),
          status: req.status,
          profile_section: req.profile_section,
          requested_by: req.requested_by_name,
          reply_summary: latest_reply&.body&.truncate(400),
          updated_at: req.updated_at
        }
      end
    end

    def reviewer_feedback_payload
      report = @company.reports.ready.order(version: :desc).first
      return [] unless report

      ReportReviewComment
        .joins(:report_review)
        .includes(:report_review)
        .where(report_reviews: { report_id: report.id })
        .order(created_at: :desc)
        .limit(REVIEWER_FEEDBACK_LIMIT)
        .map do |comment|
          {
            section_key: comment.section_key,
            body: comment.body.truncate(400),
            reviewer_name: comment.report_review.reviewer_user.name,
            report_version: report.version
          }
        end
    end

    def employee_profile_aggregate
      employees = @company.employees.where("agent_profile != '{}'::jsonb")
      employees = employees.where(department: @department) if @department

      employees.group_by { |e| e.department.presence || "general" }.map do |dept, emps|
        profiles = emps.map { |e| e.agent_profile || {} }
        {
          department: dept,
          employee_count: emps.size,
          pain_points: profiles.flat_map { |p| Array(p["pain_points"]) }.uniq.first(10),
          systems_used: profiles.flat_map { |p| Array(p["systems_used"]) }.uniq.first(10),
          workflows: profiles.flat_map { |p| Array(p["workflows"]) }.uniq.first(8),
          role_hypotheses: profiles.filter_map { |p| p["role_hypothesis"].presence }.uniq.first(8)
        }
      end
    end

    def document_inventory_payload
      docs = @company.documents.where(status: "ready")
      docs = docs.where(department: @department) if @department

      docs.order(updated_at: :desc).limit(DOCUMENT_LIMIT).map do |doc|
        meta = doc.metadata || {}
        {
          id: doc.id,
          filename: doc.filename,
          category: meta["category"],
          department: doc.department,
          source: doc.source
        }
      end
    end
  end
end
