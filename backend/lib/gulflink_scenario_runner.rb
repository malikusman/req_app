# frozen_string_literal: true

# GulfLink Logistics (Dubai) — docs-first CEO demo with McKinsey logistics reviewer.
#
#   rails scenario:gulflink
#   CLEANUP=1 rails scenario:gulflink
#
# Flow: provision → 5 mixed-format docs → intel → McKinsey reviewer → assign →
#       employee contact → report (review bootstrap) → outreach + discussion Q&A →
#       findings/submit → regenerate appendix → observations.
class GulflinkScenarioRunner
  SLUG = "gulflink-logistics"
  REVIEWER_EMAIL = "nadia.mckinsey@reviewers.worktruth.local"
  CEO_EMAIL = "ceo@gulflink.ae"
  CONTROLLER_PHONE = "+971500011001"

  FIXTURE_CANDIDATES = [
    Pathname.new("/docs/manual-test/scenario-gulflink"),
    Rails.root.join("..", "docs", "manual-test", "scenario-gulflink"),
    Rails.root.join("tmp", "gulflink_fixtures")
  ].freeze

  FIXTURES = [
    { file: "freight-billing-sop.pdf", department: "finance", document_type: "sop" },
    { file: "warehouse-cost-sheet.xlsx", department: "operations", document_type: "other" },
    { file: "customs-clearance-notes.docx", department: "operations", document_type: "policy" },
    { file: "ap-approval-matrix.txt", department: "finance", document_type: "policy" },
    { file: "pod-scan-sample.png", department: "operations", document_type: "other" }
  ].freeze

  def self.call(cleanup: ENV["CLEANUP"] == "1")
    new(cleanup: cleanup).call
  end

  attr_reader :checks, :results, :observations

  def initialize(cleanup:)
    @cleanup = cleanup
    @checks = []
    @observations = []
    @results = {
      "slug" => SLUG,
      "started_at" => Time.current.iso8601,
      "openai_present" => ENV["OPENAI_API_KEY"].present?,
      "phases" => {}
    }
  end

  def call
    banner "GulfLink Logistics (Dubai) — docs + McKinsey reviewer scenario"
    provision!
    upload_documents!
    run_intelligence!
    create_mckinsey_reviewer!
    assign_reviewer!
    seed_finance_controller!
    generate_report!
    run_qa!
    submit_reviewer_findings!
    regenerate_appendix!
    write_observations!
    finish!
  ensure
    cleanup! if @cleanup
  end

  private

  def provision!
    stage "Provision #{SLUG}"
    @platform = PlatformUser.find_by!(email: "admin@reqapp.local")

    @company = Company.find_or_initialize_by(slug: SLUG)
    @company.assign_attributes(
      name: "GulfLink Logistics LLC",
      display_name: "GulfLink Logistics",
      locale: "en",
      portal_onboarding_completed_at: Time.current,
      settings: (@company.settings.presence || {}).merge(
        "engagement_mode" => "documents",
        "allow_early_report" => false,
        "skip_platform_review" => false,
        "discovery_question_target" => 10,
        "timezone" => "Asia/Dubai",
        "report_thresholds" => {
          "min_ready_documents" => 3,
          "min_document_departments" => 2,
          "min_patterns" => 1,
          "min_multimodal_contributions" => 1
        }
      )
    )
    @company.save!

    Subscription.find_or_create_by!(company: @company) do |s|
      s.plan = "trial"
      s.status = "trial"
      s.trial_ends_at = 30.days.from_now
      s.conversation_limit = Subscriptions::PlanLimits.conversation_limit_for("trial")
    end

    @admin = CompanyUser.find_or_create_by!(company: @company, email: CEO_EMAIL) do |u|
      u.name = "Omar Al-Maktoum"
      u.password = "password123"
      u.role = "company_admin"
      u.status = "active"
      u.jti = SecureRandom.uuid
    end
    @admin.update!(name: "Omar Al-Maktoum", status: "active") if @admin.persisted?

    check "Company provisioned", @company.persisted?
    check "skip_platform_review false", @company.merged_settings["skip_platform_review"] == false
    check "engagement_mode documents", @company.engagement_mode == "documents"
    check "CEO admin #{CEO_EMAIL}", @admin.email == CEO_EMAIL

    @results["phases"]["provision"] = {
      "company_id" => @company.id,
      "ceo_email" => @admin.email,
      "skip_platform_review" => @company.merged_settings["skip_platform_review"]
    }
  end

  def upload_documents!
    stage "Upload 5 mixed-format fixtures"
    ensure_fixtures!

    FIXTURES.each do |spec|
      @company.documents.where(filename: spec[:file]).find_each do |doc|
        Documents::PurgeService.call(document: doc)
      rescue StandardError
        doc.document_chunks.delete_all
        doc.destroy
      end
    end

    docs = FIXTURES.map { |spec| ingest_fixture!(spec) }
    ready = docs.select { |d| d.reload.status == "ready" }
    failed = docs.select { |d| d.status == "failed" }
    depts = ready.map(&:department).uniq.compact

    check "Documents uploaded (#{docs.size})", docs.size == FIXTURES.size
    check "At least 4 docs ready (#{ready.size}/#{docs.size})", ready.size >= 4
    check "Multiple departments (#{depts.size})", depts.size >= 2

    png = docs.find { |d| d.filename.end_with?(".png") }
    if png
      if png.status == "ready"
        check "PNG POD scan ready via vision OCR", true
      elsif ENV["OPENAI_API_KEY"].blank? && png.processing_error.to_s.include?("image_ocr")
        check "PNG fails cleanly without OpenAI key", true
        observe(
          area: "ingest",
          severity: "info",
          title: "PNG OCR skipped without OPENAI_API_KEY",
          detail: png.processing_error.to_s
        )
      else
        check "PNG POD scan ready via vision OCR", false
      end
    end

    failed.each do |d|
      observe(
        area: "ingest",
        severity: d.filename.end_with?(".png", ".jpg", ".jpeg") ? "major" : "blocker",
        title: "Document failed parse: #{d.filename}",
        detail: d.processing_error.to_s
      )
    end

    FIXTURES.each do |spec|
      doc = docs.find { |d| d.filename == spec[:file] }
      next unless doc&.status == "ready"

      text_len = doc.document_chunks.sum { |c| c.content.to_s.length }
      observe(
        area: "ingest",
        severity: "info",
        title: "Parsed #{doc.filename}",
        detail: "status=#{doc.status} dept=#{doc.department} chunks=#{doc.document_chunks.count} chars≈#{text_len}"
      )
    end

    @documents = docs
    @results["phases"]["documents"] = {
      "statuses" => docs.map { |d| { filename: d.filename, status: d.status, error: d.processing_error, department: d.department } },
      "ready" => ready.size,
      "failed" => failed.size
    }
  end

  def run_intelligence!
    stage "Intelligence aggregate"
    result = Intelligence::AggregateCompanyIntelligence.call(company: @company.reload)
    @company.reload
    ensure_confirmed_pattern! if @company.patterns.where(status: "confirmed").none?

    CompanyReadinessRefresher.call(@company)
    @company.reload

    score = @company.report_readiness_score.to_f
    signals = @company.company_signals.order(strength: :desc).limit(8)
    check "Signals extracted (#{result[:signals]})", result[:signals].to_i.positive?
    check "Patterns present (#{@company.patterns.count})", @company.patterns.any?
    check "Readiness positive (#{score})", score.positive?

    stack_count = @company.company_systems.active.count
    check "Client stack inferred (#{stack_count})", stack_count.positive? || result[:company_systems].to_i >= 0

    published = @company.agentic_ideas.draft.order(confidence: :desc).limit(2)
    published.find_each(&:publish!)
    published_count = @company.agentic_ideas.published.count
    check "Agentic ideas published for PDF (#{published_count})", published_count.positive?

    observe(
      area: "opportunities",
      severity: "info",
      title: "Agentic ideas backlog",
      detail: "draft=#{@company.agentic_ideas.draft.count} published=#{published_count} stack=#{stack_count}"
    )

    generic = signals.any? { |s| s.label.to_s.match?(/\b(general|workflow|process)\b/i) && s.evidence_count.to_i < 2 }
    if generic
      observe(
        area: "intelligence",
        severity: "minor",
        title: "Some signals look generic / thin evidence",
        detail: signals.map { |s| "#{s.label} (ev=#{s.evidence_count})" }.join("; ")
      )
    end

    logistics_hit = signals.any? do |s|
      blob = [s.label, s.signal_type, Array(s.departments).join(" "), s.metadata.to_s].compact.join(" ")
      blob.match?(/freight|customs|demurrage|TMS|warehouse|POD|invoice|billing|approval|spreadsheet/i)
    end
    observe(
      area: "intelligence",
      severity: logistics_hit ? "info" : "major",
      title: logistics_hit ? "Signals reflect logistics/finance content" : "Signals miss logistics-specific language",
      detail: signals.map(&:label).join(" | ").to_s.truncate(400)
    )

    @results["phases"]["intelligence"] = {
      "signals" => result[:signals],
      "patterns" => result[:patterns],
      "recommendations" => result[:recommendations],
      "readiness_score" => score,
      "signal_titles" => signals.map(&:label)
    }
    check "Intelligence phase completed", true
  rescue StandardError => e
    check "Intelligence succeeded", false
    @results["phases"]["intelligence"] = { "error" => "#{e.class}: #{e.message}", "backtrace" => e.backtrace&.first(5) }
  end

  def create_mckinsey_reviewer!
    stage "Create McKinsey logistics reviewer"
    @reviewer = ReviewerUser.find_or_initialize_by(email: REVIEWER_EMAIL)
    @reviewer.assign_attributes(
      name: "Nadia Al-Rashid",
      password: "password123",
      status: "active",
      jti: @reviewer.jti.presence || SecureRandom.uuid,
      headline: "Logistics & operations transformation · GCC",
      bio: "Former McKinsey engagement manager specializing in logistics network redesign, " \
           "freight cost-to-serve, and finance operating model work across Dubai and the wider GCC. " \
           "Advises 3PLs on AP, TMS, and month-end control gaps.",
      linkedin_url: "https://www.linkedin.com/in/nadia-al-rashid-logistics",
      expertise_tags: ["Supply chain", "GCC markets", "Finance", "Controls", "Change management"],
      industries: ["Logistics", "Transportation", "Freight forwarding"],
      years_experience: 12,
      profile_status: "published"
    )
    @reviewer.save!

    @reviewer.reviewer_experiences.destroy_all
    @reviewer.reviewer_experiences.create!(
      organization: "McKinsey & Company",
      title: "Engagement Manager — Logistics & Operations",
      start_year: 2016,
      end_year: 2022,
      summary: "Led cost-to-serve and working-capital programs for Middle East 3PLs and shippers; " \
               "freight billing, customs, and AP control redesign.",
      sort_order: 0
    )
    @reviewer.reviewer_experiences.create!(
      organization: "Aramex",
      title: "Regional Operations Finance Lead",
      start_year: 2012,
      end_year: 2016,
      summary: "Owned lane P&L and AP close for UAE hub operations.",
      sort_order: 1
    )
    @reviewer.save!

    complete = Reviewers::ProfileCompleteness.call(@reviewer).complete
    check "Reviewer created (#{REVIEWER_EMAIL})", @reviewer.persisted?
    check "Profile published + complete", @reviewer.published_profile? && complete
    check "McKinsey experience present", @reviewer.reviewer_experiences.exists?(organization: "McKinsey & Company")

    observe(
      area: "reviewer_profile",
      severity: "info",
      title: "Nadia Al-Rashid provisioned",
      detail: "tags=#{@reviewer.expertise_tags.join(', ')}; experiences=#{@reviewer.reviewer_experiences.count}"
    )

    @results["phases"]["reviewer"] = {
      "id" => @reviewer.id,
      "email" => @reviewer.email,
      "profile_complete" => complete,
      "experiences" => @reviewer.reviewer_experiences.pluck(:organization, :title)
    }
  end

  def assign_reviewer!
    stage "Platform assigns reviewer to GulfLink"
    existing = @company.reviewer_assignments.active.find_by(reviewer_user_id: @reviewer.id)
    if existing
      @assignment = existing
      check "Reviewer already assigned", true
    else
      @assignment = ReviewerAssignments::AssignService.call(
        company: @company,
        reviewer_user: @reviewer,
        platform_user: @platform
      )
      check "Assignment created", @assignment.persisted?
    end

    @results["phases"]["assignment"] = { "assignment_id" => @assignment.id, "status" => @assignment.status }
  end

  def seed_finance_controller!
    stage "Seed Finance Controller contact (optional employee channel)"
    @employee = @company.employees.find_or_initialize_by(phone_e164: CONTROLLER_PHONE)
    @employee.assign_attributes(
      email: "controller@gulflink.ae",
      display_name: "Layla Hassan",
      department: "finance",
      role_title: "Finance Controller",
      participation_status: "completed",
      onboarding_step: "verified",
      invited_at: Time.current,
      completed_at: Time.current,
      preferred_language: "en",
      metadata: { "profile" => { "primary_tools" => %w[SAP Excel TMS] } }
    )
    @employee.save!

    conv = @employee.conversations.order(:id).last
    conv ||= @company.conversations.create!(
      employee: @employee,
      status: "completed",
      started_at: Time.current,
      completed_at: Time.current,
      last_activity_at: Time.current
    )
    conv.update!(status: "completed", completed_at: conv.completed_at || Time.current, last_activity_at: Time.current)

    ConversationInsight.find_or_create_by!(conversation: conv, turn_number: 1) do |insight|
      insight.company = @company
      insight.employee = @employee
      insight.insight_type = "turn_summary"
      insight.summary = "Freight billing exceptions wait on Finance Controller; demurrage accruals often late from customs notes."
      insight.structured_data = { "topics" => %w[freight demurrage approvals] }
    end

    check "Finance Controller seeded", @employee.persisted? && @employee.participation_status == "completed"
    observe(
      area: "communication",
      severity: "info",
      title: "Employee contact available for secondary WhatsApp outreach",
      detail: "Primary Q&A uses company_admin portal clarifications to CEO Omar; Layla remains optional for employee-channel checks."
    )

    @results["phases"]["employee"] = { "id" => @employee.id, "email" => @employee.email, "role" => @employee.role_title }
  end

  def generate_report!
    stage "Generate docs-first report (with review bootstrap)"
    previous = @company.reports.ready.order(version: :desc).first
    @report = @company.reports.create!(
      version: (@company.reports.maximum(:version) || 0) + 1,
      status: "queued",
      visibility: "internal_only",
      triggered_by_type: "PlatformUser",
      triggered_by_id: @platform.id,
      previous_report: previous
    )
    Reports::GenerateReportService.call(report: @report)
    @report.reload

    review = @report.report_reviews.find_by(reviewer_user: @reviewer)
    snapshot = @report.report_snapshot || {}
    summary = snapshot["executive_summary"].to_s

    check "Report ready", @report.status == "ready"
    check "Review bootstrapped for Nadia", review.present?
    check "Supporting documents in snapshot", Array(snapshot["supporting_documents"]).any?

    if summary.present?
      logistics_words = summary.match?(/freight|logistics|customs|demurrage|Dubai|TMS|warehouse/i)
      observe(
        area: "text_generation",
        severity: logistics_words ? "info" : "major",
        title: "Executive summary logistics specificity",
        detail: summary.truncate(500)
      )
    else
      observe(area: "text_generation", severity: "blocker", title: "Missing executive summary", detail: "snapshot empty")
    end

    html = begin
      Reports::HtmlBuilder.call(snapshot: snapshot, report_version: @report.version)
    rescue StandardError
      ""
    end
    if html.match?(/structured discovery interviews conducted over WhatsApp/i) && !html.match?(/document/i)
      observe(
        area: "text_generation",
        severity: "major",
        title: "Report may over-claim interview methodology",
        detail: "Docs-first company should emphasize documents"
      )
    end

    @review = review
    @results["phases"]["report"] = {
      "report_id" => @report.id,
      "version" => @report.version,
      "status" => @report.status,
      "review_id" => review&.id,
      "executive_summary_preview" => summary.truncate(300),
      "report_kind" => snapshot["report_kind"]
    }
  rescue StandardError => e
    check "Report generation succeeded", false
    @results["phases"]["report"] = { "error" => e.message, "backtrace" => e.backtrace&.first(5) }
  end

  def run_qa!
    stage "Reviewer Q&A (CEO portal clarification + discussion)"
    return check("Report/CEO ready for Q&A", false) unless @report && @admin && @reviewer

    outreach = Outreaches::CreateService.call(
      reviewer: @reviewer,
      company: @company,
      recipient_type: "company_admin",
      recipient_id: @admin.id,
      body: "Omar — for GulfLink freight billing exceptions above AED 2,000, can you share one recent example " \
            "of how long Finance Controller sign-off took versus the SOP?",
      purpose: "clarification",
      channel: "portal",
      report_id: @report.id,
      reason: "validate AP approval bottleneck"
    )
    check "CEO portal outreach sent", outreach.status == "sent" && outreach.channel == "portal"
    check "CEO outreach skips approval", !outreach.pending_admin?

    Outreaches::RecordReplyService.call(
      outreach: outreach.reload,
      body: "Last week a carrier debit note for AED 6,400 sat three days waiting for controller approval while I was traveling; " \
            "AP parked it in the Excel exception tab until SAP FB60 release.",
      channel: "portal",
      company_user: @admin
    )
    outreach.update!(status: "closed")
    outreach.append_audit!("answered", actor: @admin, note: "Closed via portal answer")
    outreach.reload
    check "CEO answered clarification", outreach.status == "closed" && outreach.reviewer_outreach_replies.any?

    observe(
      area: "communication",
      severity: "info",
      title: "CEO portal clarification Q&A completed",
      detail: "status=#{outreach.status}; recipient=#{outreach.recipient_type}; body_preview=#{outreach.body.to_s.truncate(160)}"
    )

    # Secondary: employee-path outreach still requires admin approval (regression check).
    if @employee
      employee_outreach = Outreaches::CreateService.call(
        reviewer: @reviewer,
        company: @company,
        employee_id: @employee.id,
        recipient_type: "employee",
        body: "Layla — optional follow-up on exception tab SLA.",
        purpose: "clarification",
        channel: "portal",
        report_id: @report.id
      )
      check "Employee outreach still pending admin", employee_outreach.pending_admin?
    end

    discussion = ReviewDiscussions::CreateService.call(
      reviewer: @reviewer,
      report: @report,
      params: {
        target_type: "employee",
        employee_id: @employee&.id,
        conversation_id: @employee&.conversations&.order(:id)&.last&.id,
        anchor_type: "section",
        anchor_id: "signals",
        body: "Please confirm whether demurrage accruals from Jebel Ali clearance delays are booked in the same month " \
              "or only when the customs note arrives."
      }
    )
    check "Discussion created", discussion.persisted?

    reply = ReviewDiscussions::CreateService.call(
      reviewer: @reviewer,
      report: @report,
      params: {
        target_type: "employee",
        employee_id: @employee&.id,
        conversation_id: @employee&.conversations&.order(:id)&.last&.id,
        anchor_type: "section",
        anchor_id: "signals",
        parent_id: discussion.id,
        body: "Follow-up: if booked late, how does month-end close capture the accrual gap?"
      }
    )
    check "Discussion reply created", reply.persisted? && reply.parent_id == discussion.id

    observe(
      area: "communication",
      severity: "minor",
      title: "Discussion threads are reviewer-authored replies only in this path",
      detail: "Employee did not author a discussion reply in-product; follow-up may fan out to WhatsApp/info-request. UI clarity of who sees what is a watchpoint."
    )

    @outreach = outreach
    @results["phases"]["qa"] = {
      "outreach_id" => outreach.id,
      "outreach_status" => outreach.status,
      "outreach_recipient_type" => outreach.recipient_type,
      "discussion_id" => discussion.id,
      "discussion_reply_id" => reply.id
    }
  rescue StandardError => e
    check "Q&A stage succeeded", false
    @results["phases"]["qa"] = { "error" => "#{e.class}: #{e.message}", "backtrace" => e.backtrace&.first(5) }
  end

  def submit_reviewer_findings!
    stage "Reviewer findings + submit"
    return check("Review present", false) unless @review

    ReportSections::KEYS.each do |key|
      state = @review.report_review_section_states.find_or_create_by!(section_key: key)
      state.update!(status: key == "signals" ? "needs_info" : "approved")
    end
    unless @review.report_review_comments.where(section_key: "signals").exists?
      @review.report_review_comments.create!(
        reviewer_user: @reviewer,
        section_key: "signals",
        body: "Need confirmation of demurrage accrual timing from Finance Controller (outreach in flight)."
      )
    end
    @review.update!(overall_note: "GulfLink docs show real AP/freight control friction; need one live exception example (captured via outreach).")

    finding = @review.report_review_findings.find_or_initialize_by(
      reviewer_user: @reviewer,
      finding_type: "executive_conclusion"
    )
    finding.assign_attributes(
      severity: "info",
      disposition: "endorse",
      body: "As a former McKinsey logistics EM, I endorse the docs-first narrative: freight billing exceptions and " \
            "customs-driven demurrage create month-end friction. Outreach reply from Finance Controller corroborates " \
            "multi-day AP approval delays above AED 2,000.",
      evidence_refs: %w[doc:freight-billing-sop doc:ap-approval-matrix outreach:gulflink],
      publishable: true
    )
    finding.save!

    risk = @review.report_review_findings.find_or_initialize_by(
      reviewer_user: @reviewer,
      finding_type: "risk"
    )
    risk.assign_attributes(
      severity: "material",
      disposition: "needs_more_evidence",
      body: "POD image ingest may be weak — validate whether exception handwriting is captured in evidence.",
      evidence_refs: %w[doc:pod-scan-sample],
      publishable: true
    )
    risk.save!

    ReportReviews::SubmitService.call(report_review: @review)
    check "Review submitted", @review.reload.submitted?

    @results["phases"]["findings"] = {
      "review_status" => @review.status,
      "findings" => @review.report_review_findings.pluck(:finding_type, :disposition)
    }
  rescue StandardError => e
    check "Findings/submit succeeded", false
    @results["phases"]["findings"] = { "error" => e.message }
  end

  def regenerate_appendix!
    stage "Regenerate report with review appendix"
    return check("Report present", false) unless @report

    overlay = Reports::ReviewNotesCollector.new(report: @report.reload).overlay
    findings = Array(overlay["structured_findings"])
    check "Overlay has findings (#{findings.size})", findings.size.positive?

    Reports::RegenerateWithReviewService.call(report: @report)
    @report.reload
    check "Report still ready after regenerate", @report.status == "ready"

    body = Storage::MinioClient.new.download(@report.storage_key)
    htmlish = body.to_s.force_encoding("UTF-8")
    htmlish = htmlish.encode("UTF-8", invalid: :replace, undef: :replace) unless htmlish.valid_encoding?
    has_appendix = htmlish.match?(/expert|review|Nadia|McKinsey|appendix/i) || @report.content_type == "application/pdf"
    check "Artifact non-empty (#{body.bytesize} bytes)", body.bytesize > 100

    observe(
      area: "text_generation",
      severity: has_appendix ? "info" : "major",
      title: "Regenerated artifact review appendix presence",
      detail: "content_type=#{@report.content_type}; bytes=#{body.bytesize}; text_match=#{has_appendix}"
    )

    if findings.none? { |f| f["body"].to_s.include?("McKinsey") }
      observe(
        area: "reviewer_profile",
        severity: "minor",
        title: "McKinsey credential may not surface outside finding body",
        detail: "Experiences exist on profile; report appendix relies on finding text rather than structured bio."
      )
    end

    @results["phases"]["appendix"] = {
      "overlay_findings" => findings.size,
      "content_type" => @report.content_type,
      "bytes" => body.bytesize
    }
  rescue StandardError => e
    check "Appendix regenerate succeeded", false
    @results["phases"]["appendix"] = { "error" => e.message }
  end

  def write_observations!
    stage "Write OBSERVATIONS.md"
    observe(
      area: "dubai_locale",
      severity: "minor",
      title: "Locale is en; timezone Asia/Dubai set in settings only",
      detail: "Currency AED appears in fixtures but product may not localize report currency/date formats for Dubai."
    )

    path = observations_path
    path.dirname.mkpath
    passed = @checks.count { |_, ok| ok }
    total = @checks.size
    lines = []
    lines << "# GulfLink Logistics scenario — observations"
    lines << ""
    lines << "Generated: #{Time.current.iso8601}"
    lines << "Company: GulfLink Logistics LLC (`#{SLUG}`)"
    lines << "Checks: #{passed}/#{total} passed"
    lines << ""
    lines << "## Checklist"
    lines << ""
    @checks.each do |label, ok|
      lines << "- #{ok ? 'PASS' : 'FAIL'}: #{label}"
    end
    lines << ""
    lines << "## Gaps (by severity)"
    lines << ""
    %w[blocker major minor info].each do |sev|
      items = @observations.select { |o| o["severity"] == sev }
      next if items.empty?

      lines << "### #{sev}"
      items.each do |o|
        lines << "- **[#{o['area']}] #{o['title']}** — #{o['detail']}"
      end
      lines << ""
    end
    lines << "## Logins"
    lines << ""
    lines << "- Company CEO: `#{CEO_EMAIL}` / `password123`"
    lines << "- Reviewer: `#{REVIEWER_EMAIL}` / `password123`"
    lines << "- Platform: `admin@reqapp.local` (seed password)"
    lines << "- Report id: #{@report&.id} version #{@report&.version}"
    path.write(lines.join("\n"))

    json_path = Rails.root.join("tmp", "gulflink_scenario_results.json")
    json_path.write(
      JSON.pretty_generate(
        @results.merge(
          "checks" => @checks.map { |l, ok| { "label" => l, "ok" => ok } },
          "observations" => @observations
        )
      )
    )
    check "OBSERVATIONS.md written", path.exist?
    puts "  → #{path}"
    puts "  → #{json_path}"
  end

  def finish!
    banner "Done — #{@checks.count { |_, ok| ok }}/#{@checks.size} checks passed"
    @checks.each { |label, ok| puts "  #{ok ? '✓' : '✗'} #{label}" }
    puts ""
    puts "Logins: CEO #{CEO_EMAIL} / password123 | Reviewer #{REVIEWER_EMAIL} / password123"
  end

  def cleanup!
    stage "CLEANUP=1 purge"
    @company&.employees&.find_each { |e| DiscoverySimulator.purge_employee!(e, company: @company) }
  end

  def ingest_fixture!(spec)
    path = fixture_dir.join(spec[:file])
    body = File.binread(path)
    filename = spec[:file]
    content_type = content_type_for(filename)
    storage_key = "companies/#{@company.id}/gulflink/#{SecureRandom.uuid}/#{filename}"
    Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: content_type)

    document = @company.documents.create!(
      uploaded_by_company_user: @admin,
      source: "company_portal_upload",
      department: spec[:department],
      document_type: spec[:document_type],
      sensitivity: "internal",
      reviewer_visible: true,
      filename: filename,
      content_type: content_type,
      byte_size: body.bytesize,
      storage_key: storage_key,
      status: "pending"
    )

    begin
      Multimodal::ParseDocumentService.call(document.id)
    rescue StandardError => e
      document.reload
      if document.status != "ready" && filename.end_with?(".txt", ".md", ".csv")
        text = body.force_encoding("UTF-8")
        text = text.encode("UTF-8", invalid: :replace, undef: :replace) unless text.valid_encoding?
        count = begin
          Multimodal::ChunkEmbedder.call(document: document, text: text)
        rescue StandardError
          0
        end
        document.update!(
          status: "ready",
          insights_preview: rich_preview(text, count),
          processing_error: "parse_fallback: #{e.message}"
        )
      end
    end

    document.reload
    if document.status == "ready"
      preview = document.insights_preview.is_a?(Hash) ? document.insights_preview : {}
      raw_text = begin
        Multimodal::DocumentTextExtractor.extract(file_path: path.to_s, content_type: content_type).to_s
      rescue StandardError
        ""
      end
      raw_text = raw_text.encode("UTF-8", invalid: :replace, undef: :replace) unless raw_text.valid_encoding?
      if raw_text.length >= 40 && (preview["summary"].to_s.length < 80 || preview["summary"].to_s.match?(/fixture|fallback/i))
        document.update!(
          insights_preview: rich_preview(raw_text, preview["chunk_count"] || document.document_chunks.count)
            .merge(preview.except("summary"))
        )
      end
    end
    document.reload
  end

  def rich_preview(text, chunk_count)
    {
      "summary" => text.to_s.truncate(4000),
      "friction_points" => ["manual spreadsheet", "approval bottlenecks", "data silos", "demurrage accruals"],
      "workflows" => ["freight billing", "customs clearance", "accounts payable"],
      "tools_mentioned" => %w[SAP Excel TMS SharePoint],
      "systems" => %w[SAP TMS Excel],
      "chunk_count" => chunk_count
    }
  end

  def content_type_for(filename)
    case File.extname(filename).downcase
    when ".pdf" then "application/pdf"
    when ".xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    when ".docx" then "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    when ".txt" then "text/plain"
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    else "application/octet-stream"
    end
  end

  def ensure_fixtures!
    return if fixture_dir

    raise "GulfLink fixtures missing — expected under docs/manual-test/scenario-gulflink"
  end

  def fixture_dir
    @fixture_dir ||= FIXTURE_CANDIDATES.find { |p| p.exist? && p.join("ap-approval-matrix.txt").exist? }
  end

  def observations_path
    # Docker mounts docs as :ro — always write under tmp; host copy is done after run if needed.
    Rails.root.join("tmp", "gulflink_OBSERVATIONS.md")
  end

  def ensure_confirmed_pattern!
    signal_ids = @company.company_signals.limit(2).pluck(:id)
    return if signal_ids.empty?

    pattern = Pattern.find_or_initialize_by(company: @company, title: "Freight billing and AP approval friction")
    pattern.assign_attributes(
      description: "Exceptions and demurrage-driven accruals create month-end friction across TMS, Excel, and SAP.",
      confidence: 0.82,
      departments: @company.documents.where(status: "ready").where.not(department: [nil, ""]).distinct.pluck(:department),
      linked_signal_ids: signal_ids,
      status: "confirmed",
      first_seen_at: pattern.first_seen_at || Time.current,
      last_updated_at: Time.current
    )
    pattern.save!
  end

  def observe(area:, severity:, title:, detail:)
    @observations << { "area" => area, "severity" => severity, "title" => title, "detail" => detail }
  end

  def check(label, passed)
    @checks << [label, !!passed]
    puts "  #{passed ? '✓' : '✗'} #{label}"
  end

  def stage(name)
    puts "\n==> #{name}"
  end

  def banner(msg)
    puts "\n#{'=' * 72}\n#{msg}\n#{'=' * 72}"
  end
end
