# frozen_string_literal: true

namespace :e2e do
  desc "Provision a company user with an approved, fully-rendered report for the browser tests"
  task seed_report_reader: :environment do
    abort "Refusing to run in production" if Rails.env.production?

    email = ENV.fetch("E2E_EMAIL", "reader-e2e@worktruth.test")
    password = ENV.fetch("E2E_PASSWORD", "ReaderE2E123!")

    company = Company.find_or_create_by!(slug: "reader-e2e") do |c|
      c.name = "Reader E2E Co"
      c.display_name = "Reader E2E Co"
      c.locale = "en"
    end
    # Login is gated on both of these, so a seeded company that skips them can
    # authenticate in a request spec but not in a browser.
    company.update!(
      portal_onboarding_completed_at: Time.current,
      approval_status: "approved"
    )
    subscription = company.subscription || company.build_subscription
    subscription.update!(plan: Subscription::PLANS.first, status: "active")

    user = CompanyUser.find_or_initialize_by(email: email)
    user.company = company
    user.name = "Reader E2E Admin"
    user.role = "company_admin"
    user.password = password
    user.save!

    # Signals across two departments so the report has real content and a
    # cross-department pattern -- the reader is being tested against a report
    # shaped like a real one, not an empty shell.
    %w[finance operations].each_with_index do |department, i|
      employee = Employee.find_or_initialize_by(company: company, phone_e164: "+9715009901#{i}0")
      employee.assign_attributes(
        display_name: "E2E #{department.capitalize}", department: department,
        participation_status: "completed", completed_at: Time.current
      )
      employee.save!
      conversation = Conversation.find_or_create_by!(employee: employee, company: company) do |c|
        c.status = "completed"
        c.completed_at = Time.current
      end
      # Enough matching answers that manual_process clears the 0.65 gate
      # RecommendationSynthesizer needs (1 - exp(-w/6) >= 0.65 needs w >= 6.3,
      # and w counts DISTINCT matching messages). A report with no
      # recommendations is not representative, and the reader's jump rail would
      # have no Recommendations target to test against.
      answers = [
        "We re-enter every invoice line into a spreadsheet by hand every Friday.",
        "The figures get copy-pasted into Excel manually before anyone signs off.",
        "I manually re-key the same order details into a second spreadsheet.",
        "Everything is a manual spreadsheet step, and it eats hours every week.",
        "Approvals then wait on a manager sign-off for days before anything moves."
      ]

      # Converge rather than skip: an earlier seed run may have left fewer
      # messages, and skipping would silently keep the weaker evidence.
      existing = conversation.messages.where(direction: "inbound")
      if existing.count != answers.size
        existing.destroy_all
        answers.each do |body|
          conversation.messages.create!(
            direction: "inbound", message_type: "text", channel: "web", body: body
          )
        end
      end
    end

    Intelligence::AggregateCompanyIntelligence.call(company: company.reload)
    company.update!(report_readiness_score: 100)

    report = company.reports.create!(
      version: (company.reports.maximum(:version) || 0) + 1,
      status: "queued", visibility: "internal_only",
      triggered_by_type: "CompanyUser", triggered_by_id: user.id,
      previous_report: company.reports.ready.order(version: :desc).first
    )
    Reports::GenerateReportService.call(report: report)

    # A consultant-authored section, so the reader's jump rail has to handle the
    # .expert-page case where every eyebrow reads "Expert consultant".
    consultant = ConsultantUser.find_or_initialize_by(email: "reader-e2e-consultant@worktruth.test")
    consultant.assign_attributes(
      name: "Dr E2E Reviewer", headline: "12 yrs operations", status: "active",
      password: password, expertise_tags: %w[operations finance]
    )
    consultant.save!
    template = ReportSectionTemplates.find("risks")
    report.report_section_overrides.find_or_create_by!(
      consultant_user: consultant, action: "add", section_key: template["key"]
    ) do |o|
      o.title = template["title"]
      o.anchor_section = "recommendations"
      o.published = true
      o.body = "## Execution risks\n\n**Finance will resist a new approval step.** They own the current reconciliation.\n*Mitigation.* Pilot on a single supplier first.\n\n## The risk of doing nothing\n\nThe delay compounds every quarter."
    end

    review = ReportReview.find_or_create_by!(report: report, consultant_user: consultant) do |r|
      r.company = company
      r.status = "pending"
    end
    ReportSections::KEYS.each { |k| review.report_review_section_states.find_or_create_by!(section_key: k) }
    review.report_review_section_states.each { |st| st.update!(status: "approved") }
    review.report_review_findings.find_or_create_by!(finding_type: "executive_conclusion") do |f|
      f.consultant_user = consultant
      f.severity = "material"
      f.disposition = "endorse"
      f.publishable = true
      f.body = "Fix the reconciliation step first; the rest of the roadmap gets cheaper."
    end
    review.update!(
      overall_note: "The findings hold up against comparable operations.",
      opportunity_amount: 450_000, opportunity_unit: "AED / year",
      opportunity_basis: "11-14 day cycle against an 8-day target.",
      submitted_at: Time.current, status: "approved"
    )

    Reports::RegenerateWithReviewService.call(report: report)
    report.update!(visibility: "shared_with_company", review_workflow_status: "platform_approved")
    report.reload

    puts "E2E_EMAIL=#{email}"
    puts "E2E_PASSWORD=#{password}"
    puts "E2E_REPORT_ID=#{report.id}"
    report.report_artifacts.order(:variant).each do |a|
      puts "E2E_#{a.variant.upcase}_PAGES=#{a.page_count} reader=#{a.reader_storage_key.present?}"
    end
  end
end
