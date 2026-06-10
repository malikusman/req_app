# frozen_string_literal: true

class DemoSeeder
  DEMO_EMPLOYEES = [
    {
      phone: "+14155551001",
      name: "Jordan Lee",
      department: "finance",
      role_title: "Accounts Payable Specialist",
      seniority: "individual_contributor",
      profile: { "responsibilities" => "Processing vendor invoices, reconciliations, and chasing approvals", "primary_tools" => %w[SAP Excel] },
      participation_status: "completed",
      conversation_status: "completed",
      messages: [
        { direction: "outbound", body: "Welcome! What does your typical month-end close look like?" },
        { direction: "inbound", body: "I spend hours in Excel reconciling invoices and manual approvals in email." },
        { direction: "outbound", body: "Where do bottlenecks usually appear?" },
        { direction: "inbound", body: "Manager sign-off waits 2-3 days. We re-enter data into SAP after approval." }
      ],
      insight_summary: "Manual invoice reconciliation in Excel with slow manager approvals before SAP entry."
    },
    {
      phone: "+14155551002",
      name: "Sam Rivera",
      department: "operations",
      role_title: "Logistics Coordinator",
      seniority: "team_lead",
      profile: { "responsibilities" => "Coordinating shipments and customer status updates across teams", "primary_tools" => %w[Jira Slack Excel] },
      participation_status: "completed",
      conversation_status: "completed",
      messages: [
        { direction: "outbound", body: "Tell me about your daily operations workflow." },
        { direction: "inbound", body: "We coordinate shipments via email and Slack — lots of handoffs between teams." },
        { direction: "outbound", body: "What tools do you rely on most?" },
        { direction: "inbound", body: "Spreadsheets for tracking and Jira for exceptions. Very repetitive data entry." },
        { direction: "outbound", body: "What would you automate first if you could?" },
        { direction: "inbound", body: "Status updates to customers — we copy-paste from three different systems." }
      ],
      insight_summary: "Cross-team coordination overhead with spreadsheet tracking and manual customer status updates."
    },
    {
      phone: "+14155551003",
      name: "Alex Kim",
      department: "sales",
      participation_status: "invited",
      conversation_status: nil,
      messages: [],
      insight_summary: nil
    },
    {
      phone: "+14155551004",
      name: "Taylor Morgan",
      department: "hr",
      role_title: "HR Operations Manager",
      seniority: "manager",
      profile: { "responsibilities" => "Employee onboarding, paperwork, and cross-department coordination", "team_size" => 4, "primary_tools" => %w[Workday DocuSign] },
      participation_status: "completed",
      conversation_status: "completed",
      messages: [
        { direction: "outbound", body: "How do you handle employee onboarding paperwork?" },
        { direction: "inbound", body: "Mostly manual PDFs and email — slow and tedious for everyone involved." },
        { direction: "outbound", body: "How long does onboarding typically take?" },
        { direction: "inbound", body: "Two weeks for IT access alone. We chase signatures across three departments." }
      ],
      insight_summary: "Manual onboarding paperwork with multi-department signature chasing."
    }
  ].freeze

  def self.call(slug: "acme-corp")
    new(slug: slug).call
  end

  def initialize(slug:)
    @company = Company.find_by!(slug: slug)
    @admin = @company.company_users.find_by!(role: "company_admin")
    @platform = PlatformUser.first!
    @reviewer = ReviewerUser.find_by!(email: "reviewer@reqapp.local")
  end

  def call
    puts "Demo seed for #{@company.name}..."

    DEMO_EMPLOYEES.each { |attrs| seed_employee!(attrs) }

    @company.update!(
      invited_count: @company.employees.count,
      completed_count: @company.employees.where(participation_status: "completed").count,
      employee_count: @company.employees.count,
      conversation_count: @company.conversations.count
    )

    Intelligence::AggregateCompanyIntelligence.call(company: @company)
    CompanyReadinessRefresher.call(@company)

    seed_documents!
    seed_question_feedback!
    seed_nudges!
    seed_timeline_events!
    seed_reviewer_profile!
    seed_additional_reviewers!

    report = seed_report! if @company.reports.ready.none?
    seed_approve_report!(report) if report&.status == "ready"
    seed_reviewer_activity!(report) if report

    seed_audit_logs!

    puts "Demo ready — #{@company.employees.count} employees, readiness #{@company.reload.report_readiness_score.round}%"
  end

  private

  def seed_employee!(attrs)
    employee = @company.employees.find_or_initialize_by(phone_e164: attrs[:phone])
    employee.assign_attributes(
      display_name: attrs[:name],
      department: attrs[:department],
      role_title: attrs[:role_title],
      seniority: attrs[:seniority],
      participation_status: attrs[:participation_status],
      onboarding_step: attrs[:participation_status] == "invited" ? "awaiting_name" : "verified",
      preferred_language: "en",
      invited_at: 3.days.ago,
      invited_by_company_user: @admin
    )
    employee.metadata = employee.metadata.merge("profile" => attrs[:profile]) if attrs[:profile].present?
    employee.started_at ||= 2.days.ago if attrs[:participation_status] != "invited"
    employee.completed_at ||= 1.day.ago if attrs[:participation_status] == "completed"
    employee.consent_given_at ||= 2.days.ago if attrs[:participation_status] != "invited"
    employee.verified_at ||= 2.days.ago if attrs[:participation_status] != "invited"
    employee.last_active_at = attrs[:participation_status] == "invited" ? 3.days.ago : 2.hours.ago
    employee.save!

    EmployeeAccessCode.issue_for!(employee: employee, issued_by_type: "company_user") if employee.employee_access_codes.active.none?

    return if attrs[:conversation_status].blank?

    conversation = employee.conversations.order(:created_at).first
    conversation ||= employee.conversations.create!(company: @company, status: attrs[:conversation_status])
    conversation.update!(
      status: attrs[:conversation_status],
      question_count: attrs[:messages].count { |m| m[:direction] == "outbound" },
      started_at: conversation.started_at || 2.days.ago,
      last_activity_at: 3.hours.ago,
      completed_at: attrs[:conversation_status] == "completed" ? 1.day.ago : nil
    )

    seed_messages!(conversation, attrs[:messages])
    seed_insight!(conversation, employee, attrs[:insight_summary]) if attrs[:insight_summary].present?
  end

  def seed_messages!(conversation, message_attrs)
    message_attrs.each_with_index do |attrs, index|
      conversation.messages.find_or_create_by!(body: attrs[:body]) do |m|
        m.direction = attrs[:direction]
        m.message_type = "text"
        m.is_discovery_question = attrs[:direction] == "outbound"
        m.created_at = (message_attrs.length - index).hours.ago
      end
    end
  end

  def seed_insight!(conversation, employee, summary)
    message = conversation.messages.where(direction: "inbound").order(:created_at).last
    ConversationInsight.find_or_create_by!(conversation: conversation, turn_number: 1) do |insight|
      insight.employee = employee
      insight.company = @company
      insight.message = message
      insight.summary = summary
      insight.structured_data = { "topics" => ["manual_process", "approval_bottleneck"], "pain_points" => [summary] }
    end
  end

  def seed_documents!
    [
      { filename: "month-end-checklist.pdf", department: "finance", preview: { "summary" => "Manual reconciliation steps across Excel and SAP", "topics" => %w[finance reconciliation] } },
      { filename: "onboarding-playbook.docx", department: "hr", preview: { "summary" => "Paper-based onboarding with email signature collection", "topics" => %w[hr onboarding] } }
    ].each do |attrs|
      Document.find_or_create_by!(company: @company, filename: attrs[:filename]) do |doc|
        doc.source = "company_portal_upload"
        doc.department = attrs[:department]
        doc.storage_key = "demo/#{@company.slug}/#{attrs[:filename]}"
        doc.content_type = "application/pdf"
        doc.byte_size = 48_000
        doc.status = "ready"
        doc.uploaded_by_company_user = @admin
        doc.insights_preview = attrs[:preview]
      end
    end
  end

  def seed_question_feedback!
    outbound_messages = Message.joins(:conversation)
                               .where(conversations: { company_id: @company.id }, direction: "outbound", is_discovery_question: true)
                               .order(:created_at)
                               .limit(3)

    feedbacks = %w[relevant relevant not_relevant]
    outbound_messages.each_with_index do |message, index|
      DiscoveryQuestionFeedback.find_or_create_by!(company: @company, message: message, company_user: @admin) do |f|
        f.feedback = feedbacks[index] || "relevant"
        f.note = index == 2 ? "Too generic for our finance team" : nil
      end
    end
  end

  def seed_nudges!
    alex = @company.employees.find_by!(display_name: "Alex Kim")
    conversation = alex.conversations.first
    EmployeeNudge.find_or_create_by!(employee: alex, sent_at: 1.day.ago) do |n|
      n.company_user = @admin
      n.conversation = conversation
      n.channel = "whatsapp_template"
    end
  end

  def seed_timeline_events!
    @company.conversations.where(status: "completed").includes(:employee).find_each do |conversation|
      InsightTimelineEvent.find_or_create_by!(
        company: @company,
        event_type: "interview_completed",
        target_type: "Conversation",
        target_id: conversation.id
      ) do |event|
        event.title = "Interview completed — #{conversation.employee.display_name}"
        event.summary = "Discovery session finished in #{conversation.employee.department}"
        event.occurred_at = conversation.completed_at || 1.day.ago
      end
    end
  end

  def seed_reviewer_profile!
    @reviewer.update!(
      headline: "Operations transformation · GCC · 15 yrs",
      bio: "Former Big Four operations lead helping mid-market teams cut manual work across finance, HR, and supply chain. Published playbooks on month-end close and onboarding automation.",
      linkedin_url: "https://linkedin.com/in/expert-reviewer",
      expertise_tags: %w[Finance Operations Change\ management HR],
      industries: %w[Manufacturing SaaS],
      languages: %w[English Spanish],
      timezone: "America/New_York",
      years_experience: 15,
      profile_status: "published",
      profile_completed_at: Time.current,
      platform_verified_at: 1.week.ago
    )

    ReviewerExperience.find_or_create_by!(reviewer_user: @reviewer, title: "Operations Director") do |exp|
      exp.organization = "Global Manufacturing Co"
      exp.start_year = 2015
      exp.end_year = 2022
      exp.summary = "Led finance and operations transformation across 3 regions."
      exp.sort_order = 0
    end
  end

  def seed_additional_reviewers!
    finance_reviewer = ReviewerUser.find_or_create_by!(email: "reviewer2@reqapp.local") do |u|
      u.name = "Finance Specialist"
      u.password = "password123"
      u.status = "active"
      u.jti = SecureRandom.uuid
    end
    finance_reviewer.update!(
      headline: "Finance & AP automation",
      bio: "A" * 80,
      linkedin_url: "https://linkedin.com/in/finance-specialist",
      expertise_tags: %w[Finance AP Automation],
      profile_status: "draft"
    )
    ReviewerExperience.find_or_create_by!(reviewer_user: finance_reviewer, title: "AP Manager") do |exp|
      exp.organization = "Regional Bank"
      exp.start_year = 2018
      exp.end_year = nil
      exp.summary = "Accounts payable and month-end close."
      exp.sort_order = 0
    end
  end

  def seed_report!
    previous = @company.reports.ready.order(version: :desc).first
    report = @company.reports.create!(
      version: (@company.reports.maximum(:version) || 0) + 1,
      status: "queued",
      visibility: "internal_only",
      triggered_by_type: "PlatformUser",
      triggered_by_id: @platform.id,
      previous_report: previous
    )
    Reports::GenerateReportService.call(report: report)
    puts "Report v#{report.reload.version} — #{report.status}"
    report
  rescue StandardError => e
    puts "Report generation skipped: #{e.message}"
    seed_fallback_report!
  end

  def seed_fallback_report!
    previous = @company.reports.ready.order(version: :desc).first
    delta = Reports::DeltaCalculator.call(company: @company, previous_report: previous)
    snapshot = Reports::SnapshotBuilder.call(company: @company, delta: delta)
    html = Reports::HtmlBuilder.call(snapshot: snapshot)
    storage_key = "reports/#{@company.id}/v#{(@company.reports.maximum(:version) || 0) + 1}/report.html"

    begin
      Storage::MinioClient.new.upload(key: storage_key, body: html, content_type: "text/html")
    rescue StandardError => e
      puts "MinIO upload skipped: #{e.message}"
    end

    report = @company.reports.create!(
      version: (@company.reports.maximum(:version) || 0) + 1,
      status: "ready",
      visibility: "internal_only",
      storage_key: storage_key,
      content_type: "text/html",
      report_snapshot: snapshot,
      generated_at: Time.current,
      triggered_by_type: "PlatformUser",
      triggered_by_id: @platform.id,
      previous_report: previous
    )
    ReportReviews::BootstrapService.call(report: report) if @company.reviewer_assignments.active.exists?
    report
  end

  def seed_approve_report!(report)
    return unless report.status == "ready"

    report.update!(
      visibility: "shared_with_company",
      review_workflow_status: "platform_approved",
      reviewed_by_platform_user: @platform,
      reviewed_at: Time.current
    )
  end

  def seed_reviewer_activity!(report)
    sam = @company.employees.find_by!(display_name: "Sam Rivera")
    conversation = sam.conversations.first

    info_request = ReviewerInfoRequest.find_or_create_by!(
      company: @company,
      employee: sam,
      conversation: conversation,
      reviewer_user: @reviewer,
      body: "Can you share an example of the customer status update you copy between systems?"
    ) do |req|
      req.report = report
      req.status = "replied"
      req.sent_at = 2.days.ago
    end

    reply_message = conversation.messages.find_or_create_by!(body: "Sure — I pull order status from Jira, then paste into our CRM and email template.") do |m|
      m.direction = "inbound"
      m.message_type = "text"
      m.reviewer_followup = true
      m.created_at = 1.day.ago
    end

    ReviewerInfoReply.find_or_create_by!(reviewer_info_request: info_request, message: reply_message) do |r|
      r.body = reply_message.body
      r.received_at = 1.day.ago
    end

    [
      "Reviewing executive summary — strong signal coverage from finance and ops.",
      "Should we call out the SAP re-entry issue as a cross-department pattern?",
      "Agreed. I'll flag it in the patterns section."
    ].each_with_index do |body, index|
      ReviewerChatMessage.find_or_create_by!(
        company: @company,
        sender_reviewer_user: @reviewer,
        body: body
      ) do |msg|
        msg.created_at = (3 - index).hours.ago
      end
    end

    review = ReportReview.find_or_create_by!(report: report, reviewer_user: @reviewer) do |r|
      r.company = @company
      r.status = "in_review"
    end

    ReportSections::KEYS.each do |key|
      review.report_review_section_states.find_or_create_by!(section_key: key)
    end

    review.report_review_section_states.find_by(section_key: "executive_summary")&.update!(status: "approved")
    review.report_review_comments.find_or_create_by!(report_review: review, section_key: "signals") do |c|
      c.reviewer_user = @reviewer
      c.body = "Consider highlighting the SAP re-entry bottleneck more prominently."
    end
  end

  def seed_audit_logs!
    entries = [
      { action: "company_created", target: @company, at: 2.weeks.ago },
      { action: "reviewer_assigned", target: @company, at: 1.week.ago, metadata: { reviewer_email: @reviewer.email } },
      { action: "report_generated", target: @company.reports.ready.order(version: :desc).first, at: 2.days.ago },
      { action: "report_approved", target: @company.reports.ready.order(version: :desc).first, at: 1.day.ago }
    ]

    entries.each do |entry|
      next if entry[:target].blank?

      PlatformAuditLog.find_or_create_by!(
        platform_user: @platform,
        action: entry[:action],
        target_type: entry[:target].class.name,
        target_id: entry[:target].id
      ) do |log|
        log.metadata = entry[:metadata] || {}
        log.created_at = entry[:at]
        log.updated_at = entry[:at]
      end
    end
  end
end

class BetaDemoSeeder
  DEMO_EMPLOYEES = [
    {
      phone: "+14155552001",
      name: "Casey Brooks",
      department: "operations",
      participation_status: "started",
      conversation_status: "discovery",
      messages: [
        { direction: "outbound", body: "What does your team spend the most time on each week?" },
        { direction: "inbound", body: "Chasing approvals and updating shared spreadsheets for inventory." }
      ],
      insight_summary: "Inventory tracking relies on shared spreadsheets with slow approvals."
    },
    {
      phone: "+14155552002",
      name: "Riley Chen",
      department: "finance",
      participation_status: "invited",
      conversation_status: nil,
      messages: [],
      insight_summary: nil
    }
  ].freeze

  def self.call(slug: "beta-industries")
    new(slug: slug).call
  end

  def initialize(slug:)
    @company = Company.find_by!(slug: slug)
    @admin = @company.company_users.find_by!(role: "company_admin")
    @platform = PlatformUser.first!
    @reviewer = ReviewerUser.find_by!(email: "reviewer@reqapp.local")
  end

  def call
    puts "Beta demo seed for #{@company.name}..."

    DEMO_EMPLOYEES.each { |attrs| seed_employee!(attrs) }

    @company.update!(
      invited_count: @company.employees.count,
      completed_count: @company.employees.where(participation_status: "completed").count,
      employee_count: @company.employees.count,
      conversation_count: @company.conversations.count
    )

    Intelligence::AggregateCompanyIntelligence.call(company: @company)
    CompanyReadinessRefresher.call(@company)

    report = @company.reports.ready.order(version: :desc).first || seed_report!
    seed_beta_report_review!(report) if report&.status == "ready"
    seed_beta_audit_logs!(report)

    puts "Beta demo ready — #{@company.employees.count} employees, report #{report&.review_workflow_status || 'none'}"
  end

  private

  def seed_employee!(attrs)
    employee = @company.employees.find_or_initialize_by(phone_e164: attrs[:phone])
    employee.assign_attributes(
      display_name: attrs[:name],
      department: attrs[:department],
      participation_status: attrs[:participation_status],
      onboarding_step: attrs[:participation_status] == "invited" ? "awaiting_name" : "verified",
      preferred_language: "en",
      invited_at: 2.days.ago,
      invited_by_company_user: @admin
    )
    employee.started_at ||= 1.day.ago if attrs[:participation_status] != "invited"
    employee.consent_given_at ||= 1.day.ago if attrs[:participation_status] != "invited"
    employee.verified_at ||= 1.day.ago if attrs[:participation_status] != "invited"
    employee.last_active_at = 4.hours.ago
    employee.save!

    EmployeeAccessCode.issue_for!(employee: employee, issued_by_type: "company_user") if employee.employee_access_codes.active.none?

    return if attrs[:conversation_status].blank?

    conversation = employee.conversations.order(:created_at).first
    conversation ||= employee.conversations.create!(company: @company, status: attrs[:conversation_status])
    conversation.update!(
      status: attrs[:conversation_status],
      question_count: attrs[:messages].count { |m| m[:direction] == "outbound" },
      started_at: 1.day.ago,
      last_activity_at: 4.hours.ago
    )

    attrs[:messages].each_with_index do |msg_attrs, index|
      conversation.messages.find_or_create_by!(body: msg_attrs[:body]) do |m|
        m.direction = msg_attrs[:direction]
        m.message_type = "text"
        m.is_discovery_question = msg_attrs[:direction] == "outbound"
        m.created_at = (attrs[:messages].length - index).hours.ago
      end
    end

    if attrs[:insight_summary].present?
      message = conversation.messages.where(direction: "inbound").order(:created_at).last
      ConversationInsight.find_or_create_by!(conversation: conversation, turn_number: 1) do |insight|
        insight.employee = employee
        insight.company = @company
        insight.message = message
        insight.summary = attrs[:insight_summary]
        insight.structured_data = { "topics" => ["manual_process"], "pain_points" => [attrs[:insight_summary]] }
      end
    end
  end

  def seed_report!
    previous = @company.reports.ready.order(version: :desc).first
    report = @company.reports.create!(
      version: (@company.reports.maximum(:version) || 0) + 1,
      status: "queued",
      visibility: "internal_only",
      triggered_by_type: "PlatformUser",
      triggered_by_id: @platform.id,
      previous_report: previous
    )
    Reports::GenerateReportService.call(report: report)
    puts "Beta report v#{report.reload.version} — #{report.status} / #{report.review_workflow_status}"
    report
  rescue StandardError => e
    puts "Beta report generation skipped: #{e.message}"
    seed_fallback_report!
  end

  def seed_fallback_report!
    previous = @company.reports.ready.order(version: :desc).first
    delta = Reports::DeltaCalculator.call(company: @company, previous_report: previous)
    snapshot = Reports::SnapshotBuilder.call(company: @company, delta: delta)
    html = Reports::HtmlBuilder.call(snapshot: snapshot)
    version = (@company.reports.maximum(:version) || 0) + 1
    storage_key = "reports/#{@company.id}/v#{version}/report.html"

    begin
      Storage::MinioClient.new.upload(key: storage_key, body: html, content_type: "text/html")
    rescue StandardError => e
      puts "MinIO upload skipped: #{e.message}"
    end

    report = @company.reports.create!(
      version: version,
      status: "ready",
      visibility: "internal_only",
      storage_key: storage_key,
      content_type: "text/html",
      report_snapshot: snapshot,
      generated_at: Time.current,
      triggered_by_type: "PlatformUser",
      triggered_by_id: @platform.id,
      previous_report: previous
    )
    ReportReviews::BootstrapService.call(report: report) if @company.reviewer_assignments.active.exists?
    report
  end

  def seed_beta_report_review!(report)
    review = ReportReview.find_or_create_by!(report: report, reviewer_user: @reviewer) do |r|
      r.company = @company
      r.status = "approved"
    end
    review.update!(submitted_at: 2.hours.ago, status: "approved")
    ReportSections::KEYS.each do |key|
      review.report_review_section_states.find_or_create_by!(section_key: key) do |s|
        s.status = "approved"
      end
    end
    report.update!(
      review_workflow_status: "reviews_complete",
      reviews_completed_at: 2.hours.ago,
      visibility: "internal_only"
    )
  end

  def seed_beta_audit_logs!(report)
    [
      { action: "company_created", target: @company, at: 5.days.ago },
      { action: "reviewer_assigned", target: @company, at: 4.days.ago, metadata: { reviewer_email: @reviewer.email } }
    ].each do |entry|
      PlatformAuditLog.find_or_create_by!(
        platform_user: @platform,
        action: entry[:action],
        target_type: entry[:target].class.name,
        target_id: entry[:target].id
      ) do |log|
        log.metadata = entry[:metadata] || {}
        log.created_at = entry[:at]
        log.updated_at = entry[:at]
      end
    end

    return unless report

    PlatformAuditLog.find_or_create_by!(
      platform_user: @platform,
      action: "report_generated",
      target_type: "Report",
      target_id: report.id
    ) do |log|
      log.metadata = { company_id: @company.id }
      log.created_at = 1.day.ago
      log.updated_at = 1.day.ago
    end
  end
end

class DemoScript
  def self.print_walkthrough
    puts ""
    puts "=" * 60
    puts "DEMO WALKTHROUGH"
    puts "=" * 60
    puts ""
    puts "Acme Corp (happy path — report downloadable)"
    puts "  Company portal: admin@acme.local / password123"
    puts "  → Employees, conversations, documents, intelligence, approved report"
    puts ""
    puts "Beta Industries (in review — platform must approve)"
    puts "  Company portal: admin@beta.local / password123"
    puts "  → Expiring trial, report awaiting platform approval (reviewer submitted)"
    puts ""
    puts "Platform admin"
    puts "  admin@reqapp.local / password123"
    puts "  → 2 companies, expiring trials, audit log, approve Beta report"
    puts ""
    puts "Expert reviewer"
    puts "  reviewer@reqapp.local / password123"
    puts "  reviewer2@reqapp.local / password123 (draft profile, unassigned)"
    puts "  → Acme in-progress review + follow-ups; Beta pending report"
    puts ""
    puts "Suggested flow:"
    puts "  1. Company (Acme) → dashboard, conversations, reports (download)"
    puts "  2. Reviewer → report review, follow-ups, co-reviewer chat"
    puts "  3. Platform → trials, audit, Acme intelligence, approve Beta report"
    puts "  4. Company (Beta) → verify report download after approval"
    puts "=" * 60
  end
end
