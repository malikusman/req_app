# frozen_string_literal: true

# Dry-run simulator for the full employee discovery journey.
#
# Drives the REAL production path — Meta webhook payloads through
# Whatsapp::InboundProcessor — for a simulated employee:
#
#   onboarding (name -> access code -> consent)
#   -> profiling (multi-question state machine)
#   -> agent routing (live agent service)
#   -> multi-agent discovery turns until completion
#   -> finalization + memory promotion
#
# and prints a transcript plus a PASS/FAIL report for each stage.
#
# Usage:
#   rails runner 'DiscoverySimulator.call'                       # finance IC at Acme
#   PERSONA=hr_manager rails demo:simulate                       # manager (strategic agent + team size)
#   CLEANUP=1 rails demo:simulate                                # remove sim data afterwards
class DiscoverySimulator
  MAX_TURNS = 30

  PERSONAS = {
    "finance_ic" => {
      phone: "+14155559901",
      name: "Simone Tester",
      profiling: {
        role_title: "Accounts Payable Specialist",
        department: "Finance",
        seniority: "I'm an individual contributor",
        responsibilities: "I reconcile vendor invoices in Excel and chase approval emails before entering everything into SAP",
        team_size: nil,
        tools: "SAP, Excel and Outlook"
      },
      expected_agents: %w[domain_finance process technical],
      unexpected_agents: %w[strategic],
      answers: [
        "It starts when a vendor emails an invoice and ends when SAP shows it as paid, usually 8 days later",
        "Matching invoices to purchase orders goes wrong the most — about 1 in 5 needs rework",
        "I depend on department managers for approvals, mostly chased over email and Slack",
        "Invoices sit in managers' inboxes for 2-3 days before anyone acts on them",
        "Handoffs go through email with the invoice attached, no shared tracker",
        "When something upstream changes I redo the reconciliation from scratch, maybe twice a week",
        "At quarter end the approval step breaks first, the backlog doubles",
        "SAP and Excel don't talk to each other at all, I re-enter everything by hand",
        "I copy invoice numbers, amounts and vendor codes between Excel and SAP daily",
        "I export the open invoice list to a spreadsheet because SAP reporting is too rigid",
        "When SAP is down I keep a paper list and batch-enter everything after",
        "A perfect version would auto-match POs and route approvals with reminders",
        "Honestly the weekly status email I compile could probably go away entirely",
        "That covers pretty much everything about my work"
      ]
    },
    "hr_manager" => {
      phone: "+14155559902",
      name: "Morgan Simfield",
      profiling: {
        role_title: "HR Operations Manager",
        department: "HR",
        seniority: "I'm a manager",
        responsibilities: "I run onboarding and offboarding for the whole company and manage the HR ops team",
        team_size: "There are 5 of us",
        tools: "Workday, DocuSign and Google Sheets"
      },
      expected_agents: %w[domain_hr technical strategic],
      unexpected_agents: [],
      answers: [
        "Onboarding kicks off when recruiting closes a hire and is done when the person has IT access and a signed contract",
        "IT access provisioning goes wrong most — it takes two weeks because three departments must sign off",
        "We coordinate with IT and Facilities over email threads that get lost constantly",
        "New-hire paperwork waits the longest, sometimes a week for a single signature",
        "Workday and DocuSign aren't connected, we download and re-upload PDFs manually",
        "We track everything in a Google Sheet because Workday's checklist is too inflexible",
        "If I could remove one handoff it would be the IT access request, it blocks everything else",
        "Slow onboarding delays revenue because new salespeople can't start for two weeks",
        "I proposed an automated provisioning workflow last year but IT had no budget",
        "When volume spikes during campus hiring season the signature chasing breaks down completely",
        "My team spends roughly half their week on status update emails",
        "A single intake system connected to IT ticketing would change everything",
        "That's the full picture of how onboarding works here"
      ]
    },
    "scenario_finance_ic" => {
      phone: "+14155558001",
      name: "Jordan Scenario",
      profiling: {
        role_title: "Accounts Payable Specialist",
        department: "Finance",
        seniority: "I'm an individual contributor",
        responsibilities: "I reconcile vendor invoices in Excel and chase approvals before SAP entry",
        team_size: nil,
        tools: "SAP, Excel and Outlook"
      },
      expected_agents: %w[domain_finance process technical],
      unexpected_agents: %w[strategic],
      answers: [
        "It starts when a vendor emails an invoice and ends when SAP shows it as paid, usually 8 days later",
        "Matching invoices to purchase orders goes wrong the most — about 1 in 5 needs rework",
        "During close we hit SCENARIO_GOLDEN_PHRASE_MONTH_END_FREEZE and stop non-critical posts",
        "Approvals require SCENARIO_GOLDEN_PHRASE_TRIPLE_APPROVAL across manager, finance lead, and controller",
        "We keep a SCENARIO_GOLDEN_PHRASE_SAP_SHADOW_LEDGER in Excel because SAP reporting is rigid",
        "Invoices sit in managers' inboxes for 2-3 days before anyone acts on them",
        "Handoffs go through email with the invoice attached, no shared tracker",
        "SAP and Excel don't talk to each other at all, I re-enter everything by hand",
        "At quarter end the approval step breaks first, the backlog doubles",
        "I copy invoice numbers, amounts and vendor codes between Excel and SAP daily",
        "A perfect version would auto-match POs and route approvals with reminders",
        "Honestly the weekly status email I compile could probably go away entirely",
        "That covers pretty much everything about my work"
      ]
    },
    "docs_first_finance_ic" => {
      phone: "+14155558101",
      name: "Alex DocsFirst",
      profiling: {
        role_title: "Accounts Payable Specialist",
        department: "Finance",
        seniority: "I'm an individual contributor",
        responsibilities: "I reconcile vendor invoices in Excel and chase approvals before SAP entry",
        team_size: nil,
        tools: "SAP, Excel and Outlook"
      },
      expected_agents: %w[domain_finance process technical],
      unexpected_agents: %w[strategic],
      answers: [
        "It starts when a vendor emails an invoice and ends when SAP shows it as paid",
        "Matching invoices to purchase orders goes wrong the most with manual spreadsheet work",
        "I wait on manager approval constantly — approval bottlenecks every close",
        "SAP and Excel don't talk; I re-enter everything by hand creating data silos",
        "Reconciliation is repetitive time-consuming work every week",
        "We coordinate handoffs over email and meetings across teams",
        "At quarter end the approval step breaks first",
        "I copy invoice numbers between Excel and SAP daily",
        "A perfect version would auto-match POs and route approvals",
        "That covers pretty much everything about my work"
      ]
    }
  }.freeze

  def self.call(slug: ENV.fetch("SLUG", "acme-corp"), persona: ENV.fetch("PERSONA", "finance_ic"), cleanup: ENV["CLEANUP"] == "1")
    new(slug: slug, persona: persona, cleanup: cleanup).call
  end

  attr_reader :checks, :employee, :company

  def initialize(slug:, persona:, cleanup:)
    @company = Company.find_by!(slug: slug)
    @persona_key = persona
    @persona = PERSONAS.fetch(persona) { raise ArgumentError, "Unknown persona '#{persona}'. Available: #{PERSONAS.keys.join(', ')}" }
    @cleanup = cleanup
    @checks = []
    @turns = 0
  end

  def call
    banner "Discovery dry run — #{@persona[:name]} (#{@persona_key}) @ #{@company.name}"
    execute_stages!
    print_report
    self
  ensure
    cleanup! if @cleanup
  end

  def execute_stages!
    verify_preconditions!
    reset_simulated_employee!
    create_employee!
    run_onboarding!
    run_profiling!
    run_discovery!
    run_memory_promotion!
    self
  end

  def conversation
    @conversation ||= @employee.conversations.order(:created_at).last
  end

  def self.purge_employee!(employee, company: nil)
    company ||= employee.company
    CompanyMemoryFact.where(employee_id: employee.id).delete_all
    ConversationInsight.where(employee_id: employee.id).delete_all
    ReviewerInfoRequest.where(employee_id: employee.id).find_each do |request|
      request.reviewer_info_replies.delete_all
    end
    ReviewerInfoRequest.where(employee_id: employee.id).delete_all
    EmployeeNudge.where(employee_id: employee.id).delete_all
    employee.conversations.each do |conversation|
      doc_ids = Document.where(conversation_id: conversation.id).pluck(:id)
      if doc_ids.any?
        MediaAttachment.where(conversation_id: conversation.id).update_all(document_id: nil)
        DocumentChunk.where(document_id: doc_ids).delete_all
        Document.where(id: doc_ids).delete_all
      end
      MediaAttachment.where(conversation_id: conversation.id).delete_all
      conversation.messages.delete_all
    end
    orphan_doc_ids = Document.where(employee_id: employee.id).pluck(:id)
    if orphan_doc_ids.any?
      DocumentChunk.where(document_id: orphan_doc_ids).delete_all
      Document.where(id: orphan_doc_ids).delete_all
    end
    if employee.display_name.present?
      Notification.where(company_id: company.id).where("body ILIKE ?", "%#{employee.display_name}%").delete_all
    end
    employee.conversations.delete_all
    EmployeeInvitation.where(employee_id: employee.id).delete_all
    EmployeeAccessCode.where(employee_id: employee.id).delete_all
    AccessCodeVerificationAttempt.where(employee_id: employee.id).delete_all
    EmployeeValueDigest.where(employee_id: employee.id).delete_all
    EmployeeValuePreference.where(employee_id: employee.id).delete_all
    EmployeeMarketAlert.where(employee_id: employee.id).delete_all
    EmployeeWebSession.where(employee_id: employee.id).delete_all
    MediaAttachment.where(employee_id: employee.id).delete_all
    ReviewerOutreach.where(employee_id: employee.id).delete_all if defined?(ReviewerOutreach)
    ReviewDiscussion.where(employee_id: employee.id).delete_all if defined?(ReviewDiscussion)
    employee.delete
  end

  private

  # ---------------------------------------------------------------- stages

  def verify_preconditions!
    settings = @company.merged_settings
    check "Profiling flag enabled", settings["discovery_profiling_enabled"] == true
    check "Multi-agent flag enabled", settings["discovery_multi_agent_enabled"] == true
    check "Active consent text exists", ConsentTextVersion.where(active: true).exists?
    check "Active default playbook exists", DiscoveryPlaybook.active_playbook_for("default").present?

    health = agent_service_healthy?
    check "Agent service reachable", health
    abort_run!("Agent service is not reachable — start it with `docker compose up -d langgraph`") unless health
  end

  def run_onboarding!
    stage "Onboarding"
    simulate @plain_code
    simulate "YES"

    @employee.reload
    check "Access code verified", @employee.verified_at.present?
    check "Consent recorded", @employee.consent_given_at.present?
    check "Entered profiling", conversation.status == "profiling"
  end

  def run_profiling!
    stage "Profiling"
    p = @persona[:profiling]
    answer_profiling_step "role_title", p[:role_title]
    answer_profiling_step "department", p[:department]
    answer_profiling_step "seniority", p[:seniority]
    answer_profiling_step "responsibilities", p[:responsibilities]
    answer_profiling_step "team_size", p[:team_size] if p[:team_size]
    answer_profiling_step "primary_tools", p[:tools]

    @employee.reload
    check "Profile card complete", @employee.profile_complete?
    check "Role title captured", @employee.role_title.present?
    check "Seniority parsed", @employee.seniority.present?
    check "Tools parsed (#{Array(@employee.profile_data['primary_tools']).size})",
          Array(@employee.profile_data["primary_tools"]).any?
    check "Transitioned to discovery", conversation.reload.status == "discovery"

    queue_ids = (blackboard["agent_queue"] || []).map { |a| a["id"] }
    check "Agent queue built (#{queue_ids.join(', ')})", queue_ids.any?
    @persona[:expected_agents].each do |id|
      check "  expected agent routed: #{id}", queue_ids.include?(id)
    end
    @persona[:unexpected_agents].each do |id|
      check "  agent correctly skipped: #{id}", !queue_ids.include?(id)
    end
    check "First discovery question delivered", last_outbound.present? && conversation.question_count >= 1
  end

  def run_discovery!
    stage "Discovery (multi-agent interview)"
    answers = @persona[:answers].cycle

    while conversation.reload.status == "discovery" && @turns < MAX_TURNS
      simulate answers.next
      @turns += 1
    end

    conversation.reload
    target = @company.merged_settings.fetch("discovery_question_target", 10).to_i

    check "Interview completed", conversation.status == "completed"
    check "Completed within question target (#{conversation.question_count}/#{target})",
          conversation.question_count <= target
    check "Closing message sent", last_outbound.to_s.match?(/thank/i)

    states = blackboard["agent_states"] || {}
    used = states.select { |_, s| s["questions_asked"].to_i.positive? }.keys
    check "Multiple agents participated (#{used.join(', ')})", used.size >= 2
    over_budget = states.select { |_, s| s["questions_asked"].to_i > s["question_budget"].to_i }
    check "All agents respected budgets", over_budget.empty?

    depth_limit = @company.merged_settings.fetch("discovery_max_followup_depth", 2).to_i
    too_deep = states.values.flat_map { |s| s["open_threads"] || [] }.select { |t| t["depth"].to_i > depth_limit }
    check "Follow-up depth limit respected (max #{depth_limit})", too_deep.empty?

    covered = blackboard.dig("coverage", "topics_covered") || []
    required = blackboard.dig("coverage", "topics_required") || []
    check "Coverage tracked (#{covered.size}/#{required.size}: #{covered.join(', ')})", covered.any?

    findings = blackboard["shared_findings"] || []
    check "Findings shared on blackboard (#{findings.size})", findings.any?
    check "Rolling summary maintained", blackboard["conversation_summary"].present?
    check "Insights persisted (#{insights_count})", insights_count.positive?
    check "Employee marked completed", @employee.reload.participation_status == "completed"
  end

  def run_memory_promotion!
    stage "Memory promotion"
    scope = @company.company_memory_facts.where(conversation_id: conversation.id)

    MemoryPromotionJob.perform_now(conversation.id)
    first_count = scope.count
    check "Facts promoted to company memory (#{first_count})", first_count.positive?

    MemoryPromotionJob.perform_now(conversation.id)
    check "Promotion is idempotent", scope.count == first_count
  end

  # ---------------------------------------------------------------- helpers

  def create_employee!
    @employee = @company.employees.create!(
      phone_e164: @persona[:phone],
      display_name: @persona[:name],
      participation_status: "invited",
      onboarding_step: "awaiting_access_code",
      invited_at: Time.current
    )
    _code, @plain_code = EmployeeAccessCode.issue_for!(employee: @employee, issued_by_type: "system")
  end

  def simulate(text)
    payload = {
      "entry" => [{ "changes" => [{ "value" => {
        "messages" => [{
          "from" => @persona[:phone].delete("+"),
          "id" => "wamid.sim.#{SecureRandom.hex(8)}",
          "type" => "text",
          "text" => { "body" => text }
        }],
        "contacts" => [{ "wa_id" => @persona[:phone].delete("+"), "profile" => { "name" => @persona[:name] } }]
      } }] }]
    }
    Whatsapp::InboundProcessor.new(payload).process

    shown = text == @plain_code ? "[access code]" : text
    agent = conversation.reload.blackboard["active_agent_id"]
    puts format("  %-10s %s| you: %s", conversation.status, agent ? "[#{agent}] " : "", truncate(shown, 60))
    puts format("  %-10s %s|  bot: %s", "", " " * (agent ? agent.length + 3 : 0), truncate(last_outbound.to_s, 90))
  end

  def answer_profiling_step(step, answer)
    current = conversation.reload.state_snapshot.dig("profiling", "step")
    return unless current == step

    simulate(answer)
  end

  def blackboard
    conversation.reload.blackboard
  end

  def last_outbound
    conversation.messages.where(direction: "outbound").order(:created_at).last&.body
  end

  def insights_count
    ConversationInsight.where(conversation_id: conversation.id).count
  end

  def agent_service_healthy?
    client = Langgraph::Client.new
    client.route!(thread_id: "healthcheck", profile: { "department" => "default" }, limits: {})
    true
  rescue StandardError
    false
  end

  def reset_simulated_employee!
    employee = Employee.find_by(phone_e164: @persona[:phone])
    return unless employee

    purge_employee!(employee)
  end

  def cleanup!
    stage "Cleanup"
    employee = Employee.find_by(phone_e164: @persona[:phone])
    return unless employee

    completed = employee.conversations.where(status: "completed").count
    purge_employee!(employee)
    if completed.positive?
      @company.decrement!(:completed_count, completed) if @company.completed_count >= completed
      @company.decrement!(:conversation_count, completed) if @company.conversation_count >= completed
    end
    puts "  Simulated employee and related data removed."
  end

  def purge_employee!(employee)
    self.class.purge_employee!(employee, company: @company)
  end

  # ---------------------------------------------------------------- output

  def check(label, passed)
    @checks << [label, passed]
    puts format("  %s %s", passed ? "✓" : "✗ FAIL —", label)
  end

  def stage(name)
    puts "\n— #{name} " + "-" * [60 - name.length, 5].max
  end

  def banner(text)
    puts "=" * 70
    puts text
    puts "=" * 70
  end

  def abort_run!(message)
    raise message
  end

  def print_report
    failed = @checks.reject { |_, passed| passed }
    banner format("Dry run finished — %d/%d checks passed%s",
                  @checks.size - failed.size, @checks.size,
                  failed.any? ? " — #{failed.size} FAILED" : "")
    failed.each { |label, _| puts "  ✗ #{label}" }
    unless @cleanup
      puts "\nView it in the platform portal → #{@company.name} → Conversations"
      puts "(re-run with CLEANUP=1 to remove simulated data)"
    end
    raise "Dry run failed: #{failed.map(&:first).join('; ')}" if failed.any?
  end

  def truncate(text, length)
    text.length > length ? "#{text[0, length]}…" : text
  end
end
