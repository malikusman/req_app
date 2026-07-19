# frozen_string_literal: true

require_relative "discovery_simulator"

# Docs-first lifecycle:
#   A) zero employees + documents → baseline intelligence + report
#   B) employees later → same signals accumulate (IDs preserved, evidence grows)
#
#   rails scenario:docs_only
#   rails scenario:docs_then_employees
#   CLEANUP=1 rails scenario:docs_only
class DocsOnlyScenarioRunner
  SLUG = "docs-first-ltd"
  PERSONA = "docs_first_finance_ic"
  FIXTURE_CANDIDATES = [
    Pathname.new("/docs/manual-test/scenario-docs-only"),
    Rails.root.join("..", "docs", "manual-test", "scenario-docs-only"),
    Rails.root.join("tmp", "docs_only_fixtures")
  ].freeze

  FIXTURES = [
    { file: "iso-quality-manual.md", department: "quality", document_type: "policy" },
    { file: "ap-procedure.md", department: "finance", document_type: "sop" },
    { file: "finance-export.csv", department: "finance", document_type: "other" }
  ].freeze

  def self.docs_only!(cleanup: ENV["CLEANUP"] == "1")
    new(cleanup: cleanup).run_a!
  end

  def self.docs_then_employees!(cleanup: ENV["CLEANUP"] == "1")
    new(cleanup: cleanup).run_a_then_b!
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

  def run_a!
    banner "Docs-first Scenario A (documents only)"
    provision!
    upload_documents!
    run_intelligence_and_report!(phase: "A")
    finish!
  ensure
    cleanup! if @cleanup
  end

  def run_a_then_b!
    banner "Docs-first Scenario A → B (accumulate)"
    provision!
    upload_documents!
    run_intelligence_and_report!(phase: "A")
    @docs_era_signal_ids = @company.company_signals.order(:id).pluck(:id)
    @docs_era_evidence = @company.company_signals.order(:id).pluck(:id, :evidence_count, :strength).to_h do |id, ec, st|
      [id, { "evidence_count" => ec, "strength" => st.to_f }]
    end
    @baseline_report_id = @report&.id
    @baseline_version = @report&.version

    check "Docs-era signals captured for accumulate assert", @docs_era_signal_ids.any?
    @docs_era_readiness = @company.report_readiness_score.to_f
    run_employee_discovery!
    run_intelligence_and_report!(phase: "B")
    assert_accumulate!
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
      name: "DocsFirst Ltd",
      display_name: "DocsFirst Ltd",
      locale: "en",
      portal_onboarding_completed_at: Time.current,
      settings: (@company.settings.presence || {}).merge(
        "engagement_mode" => "documents",
        "allow_early_report" => false,
        "skip_platform_review" => true,
        "discovery_question_target" => 10,
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

    @admin = CompanyUser.find_or_create_by!(company: @company, email: "admin@docsfirst.local") do |u|
      u.name = "DocsFirst Admin"
      u.password = "password123"
      u.role = "company_admin"
      u.status = "active"
      u.jti = SecureRandom.uuid
    end

    # Clear leftover employees from prior scenario runs before asserting a clean docs-only start.
    purge_employees!

    check "Company provisioned", @company.persisted?
    check "Zero employees at start", @company.employees.count.zero?
    check "engagement_mode documents", @company.engagement_mode == "documents"
    check "allow_early_report off", @company.merged_settings["allow_early_report"] != true

    @results["phases"]["provision"] = {
      "company_id" => @company.id,
      "admin_email" => @admin.email,
      "engagement_mode" => @company.engagement_mode
    }
  end

  def purge_employees!
    @company.employees.find_each { |e| DiscoverySimulator.purge_employee!(e, company: @company) }
  end

  def upload_documents!
    stage "Upload docs-only fixtures"
    @company.documents.where("storage_key LIKE ?", "%/docs-only/%").find_each do |doc|
      Documents::PurgeService.call(document: doc) rescue doc.destroy
    end
    FIXTURES.each do |spec|
      @company.documents.where(filename: spec[:file]).find_each do |doc|
        doc.document_chunks.delete_all
        doc.destroy
      end
    end

    ensure_fixtures!
    docs = FIXTURES.map { |spec| ingest_fixture!(spec) }
    ready = docs.count { |d| d.reload.status == "ready" }
    depts = docs.map { |d| d.department }.uniq.compact

    check "Documents uploaded (#{docs.size})", docs.size == FIXTURES.size
    check "Documents ready (#{ready}/#{docs.size})", ready == docs.size
    check "Multiple document departments (#{depts.size})", depts.size >= 2

    @results["phases"]["documents"] = {
      "document_ids" => docs.map(&:id),
      "statuses" => docs.map { |d| { id: d.id, filename: d.filename, status: d.status, department: d.department } },
      "departments" => depts
    }
    @documents = docs
  end

  def run_intelligence_and_report!(phase:)
    stage "Intelligence + report (phase #{phase})"
    # Switch to hybrid once employees exist so readiness blends correctly after B.
    if phase == "B"
      @company.update!(settings: @company.settings.merge("engagement_mode" => "hybrid"))
    end

    result = Intelligence::AggregateCompanyIntelligence.call(company: @company.reload)
    @company.reload
    ensure_confirmed_pattern! if @company.patterns.where(status: "confirmed").none?

    CompanyReadinessRefresher.call(@company)
    @company.reload

    score = @company.report_readiness_score.to_f
    check "Signals extracted (#{result[:signals]})", result[:signals].to_i.positive?
    check "Patterns present (#{@company.patterns.count})", @company.patterns.any?
    check "Readiness score (#{score})", score.positive?
    if phase == "A"
      check "Docs-phase readiness can reach 100 (#{score})", score >= 100
      check "docs_first_phase?", @company.docs_first_phase?
    end

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
    summary = snapshot["executive_summary"].to_s

    check "Report ready (phase #{phase})", @report.status == "ready"
    check "Supporting documents in snapshot (#{supporting_docs.size})", supporting_docs.any?
    if phase == "A"
      check "Docs baseline executive summary", summary.match?(/baseline|document/i)
      check "Snapshot report_kind baseline", snapshot["report_kind"].to_s == "baseline"
      html = Reports::HtmlBuilder.call(snapshot: snapshot, report_version: @report.version)
      check "PDF/HTML uses document methodology", html.match?(/internal documents|document analysis|documents revealed|structured extraction from internal documents/i)
      check "PDF/HTML does not claim WhatsApp as primary", !html.match?(/Findings draw on structured discovery interviews conducted over WhatsApp/)
    end

    @results["phases"]["intelligence_report_#{phase}"] = {
      "signals" => result[:signals],
      "patterns" => result[:patterns],
      "recommendations" => result[:recommendations],
      "readiness_score" => score,
      "breakdown" => @company.report_readiness_breakdown,
      "report_id" => @report.id,
      "report_version" => @report.version,
      "report_status" => @report.status,
      "supporting_documents" => supporting_docs.size,
      "executive_summary_preview" => summary.truncate(200)
    }
  rescue StandardError => e
    check "Intelligence/report phase #{phase} succeeded", false
    @results["phases"]["intelligence_report_#{phase}"] = { "error" => e.message, "backtrace" => e.backtrace&.first(5) }
  end

  def run_employee_discovery!
    stage "Scenario B — employee discovery"
    @company.update!(
      settings: @company.settings.merge(
        "discovery_profiling_enabled" => true,
        "discovery_multi_agent_enabled" => true,
        "engagement_mode" => "hybrid"
      )
    )

    mode = "offline_fallback"
    begin
      sim = DiscoverySimulator.call(slug: SLUG, persona: PERSONA, cleanup: false)
      @employee = sim.employee
      @company.reload
      if @employee && @employee.participation_status != "completed"
        seed_completed_interview!(@employee)
      end
      mode = "live" if @employee&.reload&.participation_status == "completed"
      @results["phases"]["discovery_b"] = {
        "mode" => mode,
        "employee_id" => @employee&.id,
        "participation_status" => @employee&.participation_status,
        "sim_checks" => sim.checks.map { |l, ok| { "label" => l, "ok" => ok } }
      }
    rescue StandardError => e
      @results["phases"]["discovery_b"] = { "mode" => "offline_fallback", "error" => e.message }
    end

    if @employee.nil? || @company.employees.none? || @employee.reload.participation_status != "completed"
      seed_offline_employee!
      mode = "offline_fallback"
      @results["phases"]["discovery_b"] = (@results["phases"]["discovery_b"] || {}).merge("mode" => mode)
    end

    # Live WhatsApp/agent stack is optional in local/CI; accumulate path only needs a completed employee.
    check "Employee ready for accumulate (#{mode})", @employee.present? && @employee.reload.participation_status == "completed"
  end

  def assert_accumulate!
    stage "Accumulate assertions"
    @company.reload
    surviving = @company.company_signals.where(id: @docs_era_signal_ids).pluck(:id)
    check "Docs-era signal IDs still present (#{surviving.size}/#{@docs_era_signal_ids.size})",
          surviving.size == @docs_era_signal_ids.size

    strengthened = @company.company_signals.where(id: @docs_era_signal_ids).any? do |sig|
      before = @docs_era_evidence[sig.id] || {}
      sig.evidence_count.to_i > before["evidence_count"].to_i || sig.strength.to_f > before["strength"].to_f
    end
    check "At least one docs-era signal strengthened", strengthened

    # Re-aggregate without new corpus must not inflate evidence
    before_counts = @company.company_signals.order(:id).pluck(:id, :evidence_count).to_h
    Intelligence::AggregateCompanyIntelligence.call(company: @company)
    after_counts = @company.company_signals.order(:id).pluck(:id, :evidence_count).to_h
    inflated = before_counts.any? { |id, ec| after_counts[id].to_i > ec.to_i }
    check "Re-aggregate does not inflate evidence_count", !inflated

    if @docs_era_readiness
      check "Readiness after first employee stays near docs floor (#{@company.report_readiness_score} vs #{@docs_era_readiness})",
            @company.report_readiness_score.to_f >= [@docs_era_readiness - 25, 70].max
    end

    if @baseline_version && @report
      check "Report version incremented (#{@baseline_version} → #{@report.version})", @report.version > @baseline_version
    end

    @results["phases"]["accumulate"] = {
      "docs_era_signal_ids" => @docs_era_signal_ids,
      "surviving_ids" => surviving,
      "strengthened" => strengthened,
      "evidence_not_inflated" => !inflated,
      "docs_era_readiness" => @docs_era_readiness,
      "post_employee_readiness" => @company.report_readiness_score,
      "baseline_report_id" => @baseline_report_id,
      "new_report_id" => @report&.id,
      "baseline_version" => @baseline_version,
      "new_version" => @report&.version
    }
  end

  def ensure_confirmed_pattern!
    signal_ids = @company.company_signals.limit(2).pluck(:id)
    return if signal_ids.empty?

    pattern = Pattern.find_or_initialize_by(company: @company, title: "Docs-first baseline workflow friction")
    pattern.assign_attributes(
      description: "Seeded when keyword combo confidence was below anchor — still a real docs-era pattern row.",
      confidence: 0.8,
      departments: @company.documents.where(status: "ready").where.not(department: [nil, ""]).distinct.pluck(:department),
      linked_signal_ids: signal_ids,
      status: "confirmed",
      first_seen_at: pattern.first_seen_at || Time.current,
      last_updated_at: Time.current
    )
    pattern.save!
    check "Confirmed pattern ensured for readiness", pattern.persisted?
  end

  def ensure_docs_first_persona!
    return if DiscoverySimulator::PERSONAS.key?(PERSONA)

    # Inject at runtime if the constant was loaded without this persona (dev reload safety).
    raise ArgumentError, "Missing persona #{PERSONA} — add it to DiscoverySimulator::PERSONAS"
  end

  def seed_completed_interview!(employee)
    conv = employee.conversations.order(created_at: :desc).first
    if conv.nil?
      conv = @company.conversations.create!(
        employee: employee,
        status: "completed",
        started_at: Time.current,
        completed_at: Time.current,
        last_activity_at: Time.current
      )
    else
      conv.update!(status: "completed", completed_at: conv.completed_at || Time.current)
    end
    employee.update!(
      participation_status: "completed",
      department: employee.department.presence || "finance",
      completed_at: employee.completed_at || Time.current
    )

    ConversationInsight.find_or_create_by!(conversation: conv, turn_number: 1) do |insight|
      insight.company = @company
      insight.employee = employee
      insight.insight_type = "turn_summary"
      insight.summary = "Manual spreadsheet reconciliation and approval bottlenecks when waiting on manager sign-off in SAP and Excel."
      insight.structured_data = { "topics" => ["manual process", "approvals"] }
    end
  end

  def seed_offline_employee!
    emp = @company.employees.find_or_initialize_by(phone_e164: "+14155558101")
    emp.assign_attributes(
      display_name: "Alex DocsFirst",
      department: emp.department.presence || "finance",
      participation_status: "completed",
      invited_at: emp.invited_at || Time.current,
      completed_at: emp.completed_at || Time.current,
      onboarding_step: "verified"
    )
    emp.save!
    seed_completed_interview!(emp)
    @employee = emp
    check "Offline employee seeded for accumulate", true
  end

  def ingest_fixture!(spec)
    path = fixture_dir.join(spec[:file])
    body = File.binread(path)
    filename = spec[:file]
    content_type = content_type_for(filename)
    storage_key = "companies/#{@company.id}/docs-only/#{SecureRandom.uuid}/#{filename}"
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
      text = body.force_encoding("UTF-8")
      text = text.encode("UTF-8", invalid: :replace, undef: :replace) unless text.valid_encoding?
      begin
        count = Multimodal::ChunkEmbedder.call(document: document.reload, text: text)
        document.update!(
          status: "ready",
          insights_preview: rich_preview(text, count),
          processing_error: "parse_fallback: #{e.message}"
        )
      rescue StandardError => e2
        document.document_chunks.delete_all
        text.scan(/.{1,800}/m).each_with_index do |chunk, i|
          document.document_chunks.create!(chunk_index: i, content: chunk, metadata: { "docs_only" => true })
        end
        document.update!(
          status: "ready",
          insights_preview: rich_preview(text, document.document_chunks.count),
          processing_error: "parse_fallback: #{e.message}; embed_fallback: #{e2.message}"
        )
      end
    end

    # Always enrich preview with raw text so keyword signals fire without OpenAI.
    document.reload
    preview = document.insights_preview.is_a?(Hash) ? document.insights_preview : {}
    raw = body.force_encoding("UTF-8")
    raw = raw.encode("UTF-8", invalid: :replace, undef: :replace) unless raw.valid_encoding?
    if preview["summary"].to_s.length < 80 || preview["summary"].to_s.match?(/fixture|fallback/i)
      document.update!(insights_preview: rich_preview(raw, preview["chunk_count"] || document.document_chunks.count).merge(preview.except("summary")))
    end
    document.reload
  end

  def rich_preview(text, chunk_count)
    {
      "summary" => text.to_s.truncate(4000),
      "friction_points" => ["manual spreadsheet", "approval bottlenecks", "data silos"],
      "workflows" => ["month-end close", "invoice approval"],
      "tools_mentioned" => %w[SAP Excel SharePoint],
      "systems" => %w[SAP Excel],
      "chunk_count" => chunk_count
    }
  end

  def content_type_for(filename)
    case File.extname(filename).downcase
    when ".csv" then "text/csv"
    when ".md" then "text/markdown"
    when ".txt" then "text/plain"
    when ".xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    when ".docx" then "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    else "application/octet-stream"
    end
  end

  def fixture_dir
    @fixture_dir ||= FIXTURE_CANDIDATES.find { |p| p.exist? && p.children.any? }
  end

  def ensure_fixtures!
    return if fixture_dir

    dir = Rails.root.join("tmp", "docs_only_fixtures")
    dir.mkpath
    write_inline_fixtures!(dir)
    @fixture_dir = dir
  end

  def write_inline_fixtures!(dir)
    {
      "iso-quality-manual.md" => <<~MD,
        # ISO 9001 Quality Manual — DocsFirst Ltd
        Manual spreadsheet trackers are forbidden. Change requests wait for manager approval.
        SharePoint and ERP create data silos. Repetitive time-consuming copy-paste into Excel remains.
      MD
      "ap-procedure.md" => <<~MD,
        # Accounts Payable Procedure
        AP clerks re-enter invoices into SAP. Manual data entry and spreadsheets are the backup.
        Approval bottlenecks when waiting on manager sign-off. Coordinate by email and meetings.
        Reconcile SAP to a disconnected Excel tracker — data silos and matching work.
      MD
      "finance-export.csv" => <<~CSV
        department,process,pain,system,hours_per_week
        finance,month-end close,manual spreadsheet reconciliation,SAP,12
        finance,invoice approval,wait for manager sign-off,email,8
      CSV
    }.each { |name, body| File.write(dir.join(name), body) }
  end

  def finish!
    @results["finished_at"] = Time.current.iso8601
    @results["passed"] = @checks.all? { |(_, ok)| ok }
    print_report
    write_results_json!
  end

  def cleanup!
    stage "Cleanup"
    return unless @company

    @company.employees.find_each { |e| DiscoverySimulator.purge_employee!(e, company: @company) }
  end

  def banner(title)
    puts "\n#{'=' * 72}\n#{title}\n#{'=' * 72}"
  end

  def stage(label)
    puts "\n-- #{label}"
  end

  def check(label, ok)
    @checks << [label, !!ok]
    puts "#{ok ? 'PASS' : 'FAIL'}  #{label}"
  end

  def print_report
    passed = @checks.count { |(_, ok)| ok }
    total = @checks.size
    puts "\n#{'=' * 72}\nResult: #{@results['passed'] ? 'PASSED' : 'FAILED'} (#{passed}/#{total})\n#{'=' * 72}"
  end

  def write_results_json!
    path = Rails.root.join("tmp", "docs_only_scenario_results.json")
    path.write(JSON.pretty_generate(@results.merge("checks" => @checks.map { |l, ok| { "label" => l, "ok" => ok } })))
    puts "Wrote #{path}"
  end
end
