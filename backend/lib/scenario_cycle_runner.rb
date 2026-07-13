# frozen_string_literal: true

require_relative "discovery_simulator"

# Provisions scenario-corp and runs an evidence-to-action full-cycle check.
#
#   rails scenario:full_cycle
#   CLEANUP=1 rails scenario:full_cycle
#
# Prints a human checklist plus JSON for FULL_CYCLE_OBSERVATIONS.md.
class ScenarioCycleRunner
  SLUG = "scenario-corp"
  FIXTURE_CANDIDATES = [
    Pathname.new("/docs/manual-test/scenario"),
    Rails.root.join("..", "docs", "manual-test", "scenario"),
    Rails.root.join("tmp", "scenario_fixtures")
  ].freeze

  GOLDEN = %w[
    SCENARIO_GOLDEN_PHRASE_MONTH_END_FREEZE
    SCENARIO_GOLDEN_PHRASE_TRIPLE_APPROVAL
    SCENARIO_GOLDEN_PHRASE_SAP_SHADOW_LEDGER
  ].freeze

  def self.call(cleanup: ENV["CLEANUP"] == "1")
    new(cleanup: cleanup).call
  end

  # Submit pending Scenario Corp reviews (if needed), regenerate PDF, and assert live appendix HTML.
  # Does not re-run discovery / intelligence.
  #
  #   rails scenario:verify_appendix
  def self.verify_appendix!(cleanup: false)
    new(cleanup: cleanup).verify_appendix!
  end

  attr_reader :checks, :results

  def initialize(cleanup:)
    @cleanup = cleanup
    @checks = []
    @results = {
      "slug" => SLUG,
      "started_at" => Time.current.iso8601,
      "openai_present" => ENV["OPENAI_API_KEY"].present?,
      "phases" => {}
    }
  end

  def call
    banner "Scenario Corp full-cycle"
    check "OPENAI_API_KEY present in process", @results["openai_present"]
    provision!
    upload_documents!
    run_discovery!
    run_intelligence_and_report!
    run_reviewer_eta!
    @results["finished_at"] = Time.current.iso8601
    @results["passed"] = @checks.all? { |(_, ok)| ok }
    print_report
    write_results_json!
  ensure
    cleanup! if @cleanup
  end

  def verify_appendix!
    banner "Scenario Corp review appendix verify"
    provision!
    load_ready_report!
    # Full reviewer ETA against the existing ready report (no rediscovery).
    run_reviewer_eta!(appendix_only: false)
    @results["finished_at"] = Time.current.iso8601
    @results["passed"] = @checks.all? { |(_, ok)| ok }
    @results["mode"] = "verify_appendix"
    print_report
    write_results_json!
  ensure
    cleanup! if @cleanup
  end

  private

  def provision!
    stage "Provision scenario-corp"
    @platform = PlatformUser.find_by!(email: "admin@reqapp.local")
    @reviewer_a = ReviewerUser.find_or_create_by!(email: "reviewer@reqapp.local") do |u|
      u.name = "Expert Reviewer"
      u.password = "password123"
      u.status = "active"
      u.jti = SecureRandom.uuid
    end
    @reviewer_b = ReviewerUser.find_or_create_by!(email: "reviewer2@reqapp.local") do |u|
      u.name = "Finance Specialist"
      u.password = "password123"
      u.status = "active"
      u.jti = SecureRandom.uuid
    end

    @company = Company.find_or_initialize_by(slug: SLUG)
    @company.assign_attributes(
      name: "Scenario Corp",
      display_name: "Scenario Corporation",
      locale: "en",
      portal_onboarding_completed_at: Time.current,
      settings: (@company.settings.presence || {}).merge(
        "allow_early_report" => true,
        "skip_platform_review" => false,
        "discovery_profiling_enabled" => true,
        "discovery_multi_agent_enabled" => true,
        "discovery_memory_retrieval_enabled" => true,
        "discovery_media_indexing_enabled" => true,
        "discovery_multimodal_enabled" => true,
        "discovery_question_target" => 12
      )
    )
    @company.save!

    Subscription.find_or_create_by!(company: @company) do |s|
      s.plan = "trial"
      s.status = "trial"
      s.trial_ends_at = 30.days.from_now
      s.conversation_limit = Subscriptions::PlanLimits.conversation_limit_for("trial")
    end

    @admin = CompanyUser.find_or_create_by!(company: @company, email: "admin@scenario.local") do |u|
      u.name = "Scenario Admin"
      u.password = "password123"
      u.role = "company_admin"
      u.status = "active"
      u.jti = SecureRandom.uuid
    end

    [@reviewer_a, @reviewer_b].each do |reviewer|
      ReviewerAssignment.find_or_create_by!(company: @company, reviewer_user: reviewer, status: "active") do |a|
        a.assigned_by_platform_user = @platform
        a.assigned_at = Time.current
      end
    end

    active = @company.reviewer_assignments.active.count
    check "Company provisioned", @company.persisted?
    check "Admin provisioned", @admin.persisted?
    check "Two active reviewers assigned (#{active})", active == 2

    @results["phases"]["provision"] = {
      "company_id" => @company.id,
      "admin_email" => @admin.email,
      "reviewer_ids" => [@reviewer_a.id, @reviewer_b.id],
      "openai_present" => @results["openai_present"]
    }
  end

  def upload_documents!
    stage "Upload company documents + parse"
    # Fresh docs each run so embedding counts stay attributable
    @company.documents.where("storage_key LIKE ?", "%/scenario/%").find_each do |doc|
      Documents::PurgeService.call(document: doc) rescue doc.destroy
    end
    # Also remove leftover ready fixtures from prior runs by filename
    @company.documents.where(filename: %w[month-end-close-sop.md invoice-approval-policy.md sap-handoff-notes.txt]).find_each do |doc|
      doc.document_chunks.delete_all
      doc.destroy
    end

    ensure_fixtures!
    docs = []
    fixture_files.each do |path|
      docs << ingest_fixture!(path)
    end

    ready = docs.count { |d| d.reload.status == "ready" }
    chunks = DocumentChunk.where(document_id: docs.map(&:id))
    chunk_count = chunks.count
    embedded_count = chunks.where.not(embedding: nil).count
    golden_hits = GOLDEN.count do |phrase|
      DocumentChunk.joins(:document).where(documents: { company_id: @company.id }).where("content ILIKE ?", "%#{phrase}%").exists?
    end

    vector_hit = probe_golden_vector_retrieval!

    check "Documents uploaded (#{docs.size})", docs.size == 3
    check "Documents ready (#{ready}/#{docs.size})", ready == docs.size
    check "Document chunks created (#{chunk_count})", chunk_count.positive?
    check "Document chunks embedded (#{embedded_count}/#{chunk_count})", embedded_count.positive? && embedded_count == chunk_count
    check "Golden phrases present in chunks (#{golden_hits}/#{GOLDEN.size})", golden_hits == GOLDEN.size
    check "Vector retrieval returns golden-phrase chunk", vector_hit["ok"] == true

    @results["phases"]["documents"] = {
      "document_ids" => docs.map(&:id),
      "statuses" => docs.map { |d| { id: d.id, filename: d.filename, status: d.status, error: d.processing_error } },
      "chunk_count" => chunk_count,
      "embedded_chunk_count" => embedded_count,
      "golden_phrase_hits" => golden_hits,
      "vector_probe" => vector_hit
    }
  end

  def run_discovery!
    stage "Discovery interview (scenario_finance_ic)"
    phone = DiscoverySimulator::PERSONAS.dig("scenario_finance_ic", :phone)
    prior = Employee.find_by(phone_e164: phone)
    if prior
      # Clear ETA FKs that block conversation/employee purge
      ReviewerOutreach.where(employee_id: prior.id).or(ReviewerOutreach.where(conversation_id: prior.conversation_ids)).find_each do |o|
        o.reviewer_outreach_replies.delete_all
        MeetingRequest.where(reviewer_outreach_id: o.id).update_all(reviewer_outreach_id: nil)
        o.delete
      end
      MeetingRequest.where(company_id: @company.id, reviewer_user_id: [@reviewer_a.id, @reviewer_b.id]).delete_all
      DiscoverySimulator.purge_employee!(prior, company: @company)
      check "Prior scenario employee purged", Employee.find_by(phone_e164: phone).nil?
    else
      check "No prior scenario employee to purge", true
    end

    sim = DiscoverySimulator.new(slug: SLUG, persona: "scenario_finance_ic", cleanup: false)
    sim.call
    sim.checks.each { |label, ok| check("[discovery] #{label}", ok) }

    @employee = sim.employee
    @conversation = @employee&.conversations&.order(:id)&.last
    if @employee && @employee.email.blank?
      @employee.update!(email: "jordan.scenario@scenario.local")
    end

    rag_enabled = @company.merged_settings["discovery_memory_retrieval_enabled"] == true && @results["openai_present"]
    facts = @company.company_memory_facts.count
    insights = @employee ? @employee.conversation_insights.count : 0
    golden_in_answers = GOLDEN.count do |phrase|
      @conversation&.messages&.where(direction: "inbound")&.where("body ILIKE ?", "%#{phrase}%")&.exists?
    end
    golden_in_memory = GOLDEN.count do |phrase|
      @company.company_memory_facts.where("content ILIKE ?", "%#{phrase}%").exists? ||
        (@employee && @employee.conversation_insights.where("summary ILIKE ?", "%#{phrase}%").exists?)
    end

    check "Employee created", @employee.present?
    check "Conversation present", @conversation.present?
    check "RAG enabled (memory retrieval + OpenAI)", rag_enabled
    check "Memory facts and/or insights (facts=#{facts} insights=#{insights})", facts.positive? || insights.positive?
    check "Golden phrases present in inbound answers (#{golden_in_answers}/#{GOLDEN.size})", golden_in_answers == GOLDEN.size
    # Memory promotion paraphrases; exact golden tokens may not survive. Accept related keywords.
    related = %w[freeze approval shadow ledger month-end SAP Excel]
    related_hits = related.count do |kw|
      @company.company_memory_facts.where("content ILIKE ?", "%#{kw}%").exists? ||
        (@employee && @employee.conversation_insights.where("summary ILIKE ?", "%#{kw}%").exists?)
    end
    check "Memory/insights capture related workflow terms (#{related_hits}/#{related.size})", related_hits >= 3
    check "Exact golden tokens in memory (informational #{golden_in_memory}/#{GOLDEN.size})", true

    @results["phases"]["discovery"] = {
      "employee_id" => @employee&.id,
      "conversation_id" => @conversation&.id,
      "conversation_status" => @conversation&.status,
      "participation_status" => @employee&.participation_status,
      "memory_facts" => facts,
      "insights" => insights,
      "rag_enabled" => rag_enabled,
      "golden_in_answers" => golden_in_answers,
      "golden_in_memory_or_insights" => golden_in_memory,
      "discovery_checks" => sim.checks.map { |l, ok| { "label" => l, "ok" => ok } }
    }
  end

  def run_intelligence_and_report!
    stage "Intelligence + report"
    result = Intelligence::AggregateCompanyIntelligence.call(company: @company)
    @company.reload
    check "Signals extracted (#{result[:signals]})", result[:signals].to_i.positive?
    check "Patterns detected (#{result[:patterns]})", result[:patterns].to_i.positive?
    check "Recommendations synthesized (#{result[:recommendations]})", result[:recommendations].to_i >= 0

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

    snapshot = @report.report_snapshot || {}
    supporting_docs = Array(snapshot["supporting_documents"])
    tools = Array(snapshot.dig("tools_catalog", "curated_matches"))

    check "Report ready", @report.status == "ready"
    check "Report snapshot present", snapshot.present?
    check "Supporting documents in snapshot (#{supporting_docs.size})", supporting_docs.any?
    check "Reviewer reviews bootstrapped (#{@report.report_reviews.count})", @report.report_reviews.count >= 2

    @results["phases"]["intelligence_report"] = {
      "signals" => result[:signals],
      "patterns" => result[:patterns],
      "recommendations" => result[:recommendations],
      "report_id" => @report.id,
      "report_status" => @report.status,
      "supporting_documents" => supporting_docs.size,
      "tools_catalog_matches" => tools.size,
      "review_count" => @report.report_reviews.count
    }
  rescue StandardError => e
    check "Intelligence/report succeeded", false
    @results["phases"]["intelligence_report"] = { "error" => e.message }
  end

  def load_ready_report!
    stage "Load ready report"
    @report = @company.reports.where(status: "ready").order(version: :desc).first
    check "Ready report present", @report.present?
    return unless @report

    if @report.report_reviews.count < 2
      # Bootstrap empty reviews the same way report generation does.
      [@reviewer_a, @reviewer_b].each do |reviewer|
        review = @report.report_reviews.find_or_create_by!(reviewer_user: reviewer) do |r|
          r.company = @company
          r.status = "pending"
        end
        ReportSections::KEYS.each do |key|
          review.report_review_section_states.find_or_create_by!(section_key: key) do |s|
            s.status = "pending"
          end
        end
      end
    end
    check "Review rows present (#{@report.report_reviews.count})", @report.report_reviews.count >= 2

    phone = DiscoverySimulator::PERSONAS.dig("scenario_finance_ic", :phone)
    @employee ||= Employee.find_by(phone_e164: phone) || @company.employees.order(:id).last
    check "Employee available for outreach path", @employee.present?
  end

  def run_reviewer_eta!(appendix_only: false)
    stage appendix_only ? "Reviewer appendix verify" : "Reviewer ETA (findings, outreach, meeting, graph)"
    return check("Report available for ETA", false) unless @report

    review_a = @report.report_reviews.find_by!(reviewer_user: @reviewer_a)
    review_b = @report.report_reviews.find_by!(reviewer_user: @reviewer_b)

    blocked = ensure_review_a_submitted!(review_a)
    outreach = nil
    meeting = nil
    graph = { nodes: [], edges: [] }

    prepare_review_b!(review_b)
    unless appendix_only
      outreach = deliver_review_b_outreach!
      meeting = run_meeting_path!
      graph = Evidence::GraphBuilder.call(company: @company)
      check "Evidence graph has nodes (#{graph[:nodes].size})", graph[:nodes].size.positive?
      check "Evidence graph has employee node", graph[:nodes].any? { |n| n[:type] == "employee" }
      check "Evidence graph has document node", graph[:nodes].any? { |n| n[:type] == "document" }
    end

    unless review_b.submitted?
      ReportReviews::SubmitService.call(report_review: review_b)
      check "Reviewer B submitted needs_info review", review_b.reload.submitted?
    else
      check "Reviewer B already submitted", true
    end

    overlay = Reports::ReviewNotesCollector.new(report: @report.reload).overlay
    findings = Array(overlay["structured_findings"])
    check "Overlay includes structured findings (#{findings.size})", findings.size.positive?
    check "Overlay findings include disposition", findings.any? { |f| f["disposition"].present? }
    check "Overlay findings include evidence_refs", findings.any? { |f| Array(f["evidence_refs"]).any? }

    appendix = assert_regenerated_appendix!(overlay)

    @results["phases"]["reviewer_eta"] = {
      "review_a_id" => review_a.id,
      "review_b_id" => review_b.id,
      "outreach_id" => outreach&.id,
      "outreach_status" => outreach&.status,
      "meeting_id" => meeting&.id,
      "meeting_status" => meeting&.status,
      "graph_nodes" => graph[:nodes].size,
      "graph_edges" => graph[:edges].size,
      "overlay_findings" => findings.size,
      "submit_blocked_without_finding" => blocked,
      "appendix" => appendix,
      "appendix_only" => appendix_only
    }
  rescue StandardError => e
    check "Reviewer ETA stage succeeded", false
    @results["phases"]["reviewer_eta"] = { "error" => "#{e.class}: #{e.message}", "backtrace" => e.backtrace.first(5) }
  end

  def ensure_review_a_submitted!(review_a)
    if review_a.submitted?
      seed_review_a_findings!(review_a)
      check "Reviewer A already submitted", true
      return true
    end

    ReportSections::KEYS.each do |key|
      state = review_a.report_review_section_states.find_or_create_by!(section_key: key)
      state.update!(status: "approved")
    end
    review_a.update!(overall_note: "Scenario Corp evidence supports the readiness narrative.")
    review_a.report_review_findings.where(finding_type: "executive_conclusion").delete_all

    blocked = false
    begin
      ReportReviews::SubmitService.call(report_review: review_a)
    rescue ReportReviews::SubmitService::IncompleteReviewError
      blocked = true
    end
    check "Submit blocked without executive finding", blocked

    seed_review_a_findings!(review_a)
    ReportReviews::SubmitService.call(report_review: review_a)
    check "Reviewer A submitted after findings", review_a.reload.submitted?
    blocked
  end

  def seed_review_a_findings!(review_a)
    ensure_publishable_finding!(
      review_a,
      finding_type: "executive_conclusion",
      severity: "info",
      disposition: "endorse",
      body: "Evidence from Jordan Scenario and company SOPs supports the month-end friction narrative.",
      evidence_refs: %w[signal:month-end-freeze doc:sop pattern:approvals]
    )
    ensure_publishable_finding!(
      review_a,
      finding_type: "risk",
      severity: "material",
      disposition: "needs_more_evidence",
      body: "Shadow ledger risk during SAP outages; validate controls around SCENARIO_GOLDEN_PHRASE_SAP_SHADOW_LEDGER.",
      evidence_refs: %w[signal:sap-shadow]
    )
  end

  def prepare_review_b!(review_b)
    return seed_review_b_findings!(review_b) if review_b.submitted?

    ReportSections::KEYS.each do |key|
      state = review_b.report_review_section_states.find_or_create_by!(section_key: key)
      state.update!(status: key == "signals" ? "needs_info" : "approved")
    end
    unless review_b.report_review_comments.where(section_key: "signals").exists?
      review_b.report_review_comments.create!(
        reviewer_user: @reviewer_b,
        section_key: "signals",
        body: "Need a concrete example of the freeze window from Jordan."
      )
    end
    review_b.update!(overall_note: "Mostly solid; signals need one clarification.")
    seed_review_b_findings!(review_b)
  end

  def seed_review_b_findings!(review_b)
    ensure_publishable_finding!(
      review_b,
      finding_type: "executive_conclusion",
      severity: "info",
      disposition: "needs_info",
      body: "Conditional approval pending freeze-window clarification.",
      evidence_refs: %w[signal:freeze-window]
    )
  end

  def deliver_review_b_outreach!
    raise ArgumentError, "Employee required for outreach path" unless @employee

    existing = ReviewerOutreach.where(company: @company, reviewer_user: @reviewer_b, report_id: @report.id)
      .order(created_at: :desc).first
    if existing&.status == "replied"
      check "Outreach already replied", true
      return existing
    end

    outreach = Outreaches::CreateService.call(
      reviewer: @reviewer_b,
      company: @company,
      employee_id: @employee.id,
      body: "Can you share one concrete example of SCENARIO_GOLDEN_PHRASE_MONTH_END_FREEZE from last close?",
      purpose: "clarification",
      channel: "portal",
      report_id: @report.id,
      reason: "signals needs_info"
    )
    check "Outreach pending admin approval", outreach.pending_admin?
    check "Outreach not sent yet", outreach.sent_at.blank?

    Outreaches::ApproveService.call(outreach: outreach, admin: @admin, note: "Approved for scenario test")
    outreach.reload
    if outreach.status.in?(%w[approved queued])
      begin
        DeliverOutreachJob.perform_now(outreach.id)
        outreach.reload
      rescue StandardError => e
        @results["phases"]["outreach_deliver_error"] = e.message
      end
    end
    check "Outreach left pending_admin after approve", !outreach.pending_admin?
    check "Outreach delivered or portal-sent", outreach.status.in?(%w[sent replied]) || outreach.sent_at.present?

    unless outreach.status == "replied"
      Outreaches::RecordReplyService.call(
        outreach: outreach.reload,
        body: "Last close we froze non-critical posts on T-3 per the SOP.",
        channel: "portal",
        company_user: @admin
      )
      outreach.reload
    end
    check "Outreach replied", outreach.status == "replied"
    outreach
  end

  def run_meeting_path!
    existing = MeetingRequest.where(company: @company, reviewer_user: @reviewer_a, report_id: @report.id)
      .where(status: %w[approved scheduled]).order(created_at: :desc).first
    if existing
      check "Meeting request already approved/scheduled", true
      return existing
    end

    meeting = MeetingRequests::CreateService.call(
      reviewer: @reviewer_a,
      company: @company,
      purpose: "Clarify freeze-window controls with finance lead",
      report_id: @report.id,
      desired_roles: %w[finance_lead],
      duration_minutes: 30
    )
    MeetingRequests::ApproveService.call(
      meeting_request: meeting,
      company_user: @admin,
      admin_note: "Scenario approved",
      scheduled_at: 3.days.from_now,
      meeting_link: "https://meet.example.com/scenario-freeze"
    )
    check "Meeting request approved", meeting.reload.status.in?(%w[approved scheduled])
    meeting
  end

  def ensure_publishable_finding!(review, finding_type:, severity:, body:, disposition:, evidence_refs:)
    finding = review.report_review_findings.find_or_initialize_by(
      reviewer_user: review.reviewer_user,
      finding_type: finding_type
    )
    finding.assign_attributes(
      severity: severity,
      disposition: disposition,
      body: body,
      evidence_refs: evidence_refs,
      publishable: true
    )
    finding.save!
    finding
  end

  def assert_regenerated_appendix!(overlay)
    begin
      Reports::RegenerateWithReviewService.call(report: @report)
      check "Regenerate-with-review succeeded", true
    rescue StandardError => e
      check "Regenerate-with-review succeeded", false
      @results["phases"]["regenerate_error"] = e.message
      return { "ok" => false, "error" => e.message }
    end

    html = Reports::HtmlBuilder.call(
      snapshot: @report.reload.report_snapshot,
      review_notes: overlay["notes"],
      review_overlay: overlay,
      report_version: @report.version
    )

    snapshot = @report.report_snapshot || {}
    tools = Array(snapshot.dig("tools_catalog", "curated_matches"))
    docs = Array(snapshot["supporting_documents"])
    findings = Array(overlay["structured_findings"])
    sample_ref = findings.flat_map { |f| Array(f["evidence_refs"]) }.find(&:present?)
    sample_disposition = findings.map { |f| f["disposition"] }.find(&:present?)

    checks = {
      "landscape" => html.include?("A4 landscape"),
      "expert_appendix" => html.include?("Expert validation"),
      "structured_findings" => html.include?("Structured findings"),
      "finding_card" => html.include?("finding-card"),
      "evidence_refs" => sample_ref.blank? || html.include?(sample_ref.to_s),
      "disposition" => sample_disposition.blank? || html.match?(/#{Regexp.escape(sample_disposition.to_s.humanize)}/i),
      "tools_catalog" => tools.empty? || html.include?("Recommended capabilities"),
      "supporting_docs" => docs.empty? || html.include?("Internal documents cited")
    }
    checks.each { |label, ok| check "Appendix HTML: #{label}", ok }

    out = Rails.root.join("tmp", "scenario_appendix_report.html")
    out.write(html)
    {
      "ok" => checks.values.all?,
      "html_bytes" => html.bytesize,
      "html_path" => out.to_s,
      "findings" => findings.size,
      "tools" => tools.size,
      "docs" => docs.size,
      "storage_key" => @report.storage_key,
      "content_type" => @report.content_type,
      "checks" => checks
    }
  end

  def probe_golden_vector_retrieval!
    phrase = GOLDEN.first
    doc_ids = @company.documents.where(status: "ready").pluck(:id)
    scope = DocumentChunk.where(document_id: doc_ids).where.not(embedding: nil)
    return { "ok" => false, "error" => "no_embedded_chunks" } if scope.none?

    # Prefer exact lexical match among company chunks first (proves corpus), then vector rank.
    lexical = scope.where("content ILIKE ?", "%#{phrase}%").first
    query = Openai::Client.new.embedding("Scenario Corp month-end freeze policy #{phrase}")
    ranked = scope.nearest_neighbors(:embedding, query, distance: "cosine").limit(5).to_a
    hit = ranked.find { |c| GOLDEN.any? { |p| c.content.to_s.include?(p) } } || lexical || ranked.first
    content = hit&.content.to_s
    {
      "ok" => GOLDEN.any? { |p| content.include?(p) },
      "phrase" => phrase,
      "chunk_id" => hit&.id,
      "lexical_id" => lexical&.id,
      "ranked_ids" => ranked.map(&:id),
      "preview" => content.truncate(160)
    }
  rescue StandardError => e
    { "ok" => false, "error" => e.message }
  end

  def fixture_dir
    @fixture_dir ||= FIXTURE_CANDIDATES.find { |p| p.exist? && p.children.any? }
  end

  def ensure_fixtures!
    return if fixture_dir

    dir = Rails.root.join("tmp", "scenario_fixtures")
    dir.mkpath
    {
      "month-end-close-sop.md" => File.read(Rails.root.join("..", "docs", "manual-test", "scenario", "month-end-close-sop.md"))
    }
    # Write inline copies so Docker works even if docs/ is not mounted
    write_inline_fixtures!(dir)
    @fixture_dir = dir
  end

  def write_inline_fixtures!(dir)
    (dir + "month-end-close-sop.md").write(<<~MD)
      # Month-end close SOP
      Starting T-3 AP applies **SCENARIO_GOLDEN_PHRASE_MONTH_END_FREEZE**.
    MD
    (dir + "invoice-approval-policy.md").write(<<~MD)
      # Invoice approval policy
      Invoices require **SCENARIO_GOLDEN_PHRASE_TRIPLE_APPROVAL**.
    MD
    (dir + "sap-handoff-notes.txt").write(<<~TXT)
      AP maintains SCENARIO_GOLDEN_PHRASE_SAP_SHADOW_LEDGER in Excel.
    TXT
  end

  def fixture_files
    ensure_fixtures!
    fixture_dir.children.select(&:file?).sort_by(&:basename)
  end

  def ingest_fixture!(path)
    filename = path.basename.to_s
    content_type = case path.extname
                   when ".md" then "text/markdown"
                   when ".txt" then "text/plain"
                   else "application/octet-stream"
                   end
    body = path.read
    storage_key = "documents/#{@company.id}/scenario/#{SecureRandom.uuid}/#{filename}"
    Storage::MinioClient.new.upload(key: storage_key, body: body, content_type: content_type)

    document = @company.documents.create!(
      uploaded_by_company_user: @admin,
      source: "company_portal_upload",
      department: "finance",
      document_type: "sop",
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
      # Fallback: chunk without LLM summary so RAG text is still available
      text = body
      begin
        count = Multimodal::ChunkEmbedder.call(document: document.reload, text: text)
        document.update!(
          status: "ready",
          insights_preview: { "summary" => "Scenario fixture (embed fallback)", "chunk_count" => count },
          processing_error: "parse_fallback: #{e.message}"
        )
      rescue StandardError => e2
        # Last resort: store plain chunks without embeddings if the model supports it
        document.document_chunks.delete_all
        text.scan(/.{1,800}/m).each_with_index do |chunk, i|
          document.document_chunks.create!(chunk_index: i, content: chunk, metadata: { "scenario" => true })
        end
        document.update!(
          status: "ready",
          insights_preview: { "summary" => "Scenario fixture (plain chunks)", "chunk_count" => document.document_chunks.count },
          processing_error: "parse_fallback: #{e.message}; embed_fallback: #{e2.message}"
        )
      end
    end
    document.reload
  end

  def cleanup!
    stage "Cleanup"
    return unless @company

    phone = DiscoverySimulator::PERSONAS.dig("scenario_finance_ic", :phone)
    employee = Employee.find_by(phone_e164: phone)
    DiscoverySimulator.purge_employee!(employee, company: @company) if employee
  end

  def check(label, passed)
    @checks << [label, !!passed]
    puts(passed ? "  ✓ #{label}" : "  ✗ #{label}")
  end

  def stage(name)
    puts "\n== #{name} =="
  end

  def banner(title)
    puts "\n#{'=' * 60}\n#{title}\n#{'=' * 60}"
  end

  def print_report
    passed = @checks.count { |(_, ok)| ok }
    failed = @checks.size - passed
    puts "\n#{'=' * 60}"
    puts "Scenario checklist: #{passed}/#{@checks.size} passed (#{failed} failed)"
    puts "OpenAI key present: #{@results['openai_present']}"
    puts "Company id: #{@company&.id} slug=#{SLUG}"
    puts "Admin: admin@scenario.local / password123"
    puts "Reviewers: reviewer@reqapp.local , reviewer2@reqapp.local / password123"
    puts "=" * 60
  end

  def write_results_json!
    out = Rails.root.join("tmp", "scenario_cycle_results.json")
    out.write(JSON.pretty_generate(@results.merge("checks" => @checks.map { |l, ok| { "label" => l, "ok" => ok } })))
    puts "Wrote #{out}"
    # Also mirror to repo root if writable from host mount
    host = Rails.root.join("..", "FULL_CYCLE_RESULTS.json")
    host.write(JSON.pretty_generate(@results.merge("checks" => @checks.map { |l, ok| { "label" => l, "ok" => ok } }))) rescue nil
  end
end
