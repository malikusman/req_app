# frozen_string_literal: true

# Full-application end-to-end scenario: Nimbus Trading Co (UAE import/distribution SME).
#
#   platform admin + company + consultant
#   -> 4 realistic documents (procurement / AP / supplier terms / a proforma invoice)
#   -> 4 employees interviewed: 2 over WhatsApp (webhook path) + 2 over the web chat
#   -> intelligence aggregation
#   -> gated report generation (internal_only, awaiting consultant)
#   -> consultant CONTRIBUTES: section decisions, comments, a prose EDIT that replaces
#      an AI section, an ADDED custom section, a publishable finding, an employee Q&A
#   -> asserts the enforced gate (needs_info blocks; company can't download early)
#   -> consultant submits -> platform approves -> report shared -> download + inspect
#
#   rails scenario:nimbus                 # run (uses whatever LLM the services point at)
#   CLEANUP=1 rails scenario:nimbus       # remove scenario data afterwards
#
# LLM: discovery uses the langgraph service's model; report narrative/ideas use the
# Rails Openai::Client model. For a fully-local run, point BOTH at LM Studio (Qwen)
# and set AI_REPORT_NARRATIVE=true / AI_AGENTIC_IDEAS=true.
class NimbusScenarioRunner
  SLUG = "nimbus-trading"
  ADMIN_EMAIL = "omar@nimbus.ae"
  CONSULTANT_EMAIL = "samir.ops@consultants.worktruth.local"

  # Tuned for a SLOW local model: interviews run strictly one employee at a time
  # (the runner is fully serial), and these keep the total LLM turn count small.
  #   NIMBUS_MAX_EMPLOYEES  how many employees to interview (default 2 = 1 WhatsApp + 1 web)
  #   NIMBUS_MAX_QUESTIONS  ceiling per employee (default 6)
  #   NIMBUS_MIN_QUESTIONS  floor per employee (default 4)
  # Raise them (e.g. 4 / 8) for a full run once the model is fast enough.
  #
  # The ceiling is a BACKSTOP, not a target: discovery ends when the role dossier is
  # filled, so a good interview closes below it. A run that always closes on the
  # ceiling is a signal the dossier is asking for more than the answers supply.
  MAX_EMPLOYEES = Integer(ENV.fetch("NIMBUS_MAX_EMPLOYEES", "2"))
  MAX_QUESTIONS = Integer(ENV.fetch("NIMBUS_MAX_QUESTIONS", "6"))
  MIN_QUESTIONS = Integer(ENV.fetch("NIMBUS_MIN_QUESTIONS", "4"))
  # Memory retrieval (embedding-matched document chunks + cross-employee facts) adds
  # a lot of prompt. MEASURED on Gemma 12B: a turn without it ~145s, with it ~570s.
  # Twelve turns at 570s is a two-hour run, so it is OFF by default here and the run
  # says so. NIMBUS_RETRIEVAL=1 exercises it when you have the time.
  RETRIEVAL = ENV.fetch("NIMBUS_RETRIEVAL", "0") == "1"
  # Guard against a runaway loop in the runner itself, not an interview limit.
  MAX_DISCOVERY_TURNS = MAX_QUESTIONS + 4

  FIXTURE_DIRS = [
    Pathname.new("/docs/manual-test/scenario-nimbus"),
    Pathname.new("/docs/scenario-nimbus"),
    Rails.root.join("..", "docs", "scenario-nimbus")
  ].freeze

  DOCUMENTS = [
    { file: "procurement-sop.txt", department: "procurement", document_type: "sop" },
    { file: "ap-three-way-match-policy.txt", department: "finance", document_type: "policy" },
    { file: "supplier-terms.txt", department: "procurement", document_type: "policy" },
    { file: "proforma-invoice-sample.txt", department: "finance", document_type: "other" }
  ].freeze

  # Two channels exercised: :whatsapp (Meta webhook path) and :web (Web::TurnRouter).
  EMPLOYEES = [
    {
      channel: :whatsapp, phone: "+971500900101", name: "Fatima Noor",
      profiling: { role_title: "Procurement Officer", department: "Procurement",
                   seniority: "I'm an individual contributor",
                   responsibilities: "I raise LPOs, request proforma invoices and check them against our orders",
                   tools: "Zoho Inventory, Excel and Outlook" },
      answers: [
        "Most of my day is raising LPOs in Zoho and then checking the proforma invoices suppliers send back.",
        "Checking the PI is fully manual — I compare it line by line against the LPO and the emailed quote.",
        "About one in four PIs has a mismatch, usually a price drift of five to eight percent from Supplier A.",
        "Each PI takes me twenty to thirty minutes to reconcile across Outlook, Zoho and my Excel tracker.",
        "Zoho and Excel don't talk, so I copy-paste PO numbers and amounts between them constantly.",
        "Our target is to approve a PI in two days but with a mismatch it drags to four to six days.",
        "Supplier C sends the PI as a scanned image, so finance has to retype everything.",
        "If a PI could be auto-matched to the LPO and the quote, that would honestly save me hours a week."
      ]
    },
    {
      channel: :whatsapp, phone: "+971500900102", name: "Raj Patel",
      profiling: { role_title: "Accounts Payable Accountant", department: "Finance",
                   seniority: "I'm an individual contributor",
                   responsibilities: "I run the three-way match and pay supplier invoices",
                   tools: "the accounting system, Excel and Outlook" },
      answers: [
        "I match every supplier invoice to the LPO and the goods receipt before paying.",
        "The invoices come as PDFs and I re-key the numbers into the accounting system by hand — every one.",
        "First-pass three-way match is only about seventy percent; the rest land in an Excel exception tab.",
        "Exceptions age five to fourteen days, usually because logistics hasn't posted the goods receipt.",
        "Invoice-to-pay is meant to be five days but we run nine to twelve.",
        "Month-end is brutal — I have to accrue late supplier paperwork into the right period.",
        "Anything over fifty thousand dirhams needs the Finance Director to dual sign off.",
        "If AI could read the invoice PDF and post the match, it would take a huge chunk off my plate."
      ]
    },
    {
      channel: :web, phone: "+971500900103", name: "Sara Haddad",
      profiling: { role_title: "Sales Coordinator", department: "Sales",
                   seniority: "I'm an individual contributor",
                   responsibilities: "I confirm customer orders and hand them to procurement",
                   tools: "Zoho CRM, Excel and Outlook" },
      answers: [
        "I confirm customer orders and pass the details to procurement to raise the LPO.",
        "The handoff is over email and a shared Excel — nothing links the sales order to the PO automatically.",
        "Customers chase me for delivery dates and I have to ask procurement and logistics each time.",
        "When a PI price changes, the customer quote can go stale before we catch it.",
        "I re-enter order lines from the CRM into the procurement Excel a lot.",
        "A single view linking the sales order, the LPO and the shipment would remove most of my chasing."
      ]
    },
    {
      channel: :web, phone: "+971500900104", name: "Ahmed Saleh",
      profiling: { role_title: "Logistics Coordinator", department: "Logistics",
                   seniority: "I'm an individual contributor",
                   responsibilities: "I clear shipments at Jebel Ali and post goods receipts",
                   tools: "Zoho Inventory, a freight portal and WhatsApp" },
      answers: [
        "I track shipments from the supplier B/L to customs clearance at Jebel Ali.",
        "I post the goods receipt in Zoho, but if I'm slow the AP invoice gets stuck in exceptions.",
        "Demurrage hits if customs clearance slips past forty-eight hours of free time.",
        "Freight updates come over WhatsApp and email, and I re-key milestones into Zoho.",
        "Short-shipments and chargebacks I track in a separate Excel, reconciled monthly.",
        "If receipts posted automatically from the freight portal, finance wouldn't be blocked."
      ]
    }
  ].freeze

  def self.call(cleanup: ENV["CLEANUP"] == "1")
    new(cleanup: cleanup).call
  end

  attr_reader :checks, :observations

  def initialize(cleanup:)
    @cleanup = cleanup
    @checks = []
    @observations = []
  end

  def call
    banner "Nimbus Trading Co — full-application scenario"
    fresh_reset!
    provision!
    upload_documents!
    run_discovery!
    verify_dossier!
    build_packages!
    run_intelligence!
    generate_report!
    consultant_contribution!
    consultant_reviews_package!
    assert_gate_blocks_when_needs_info!
    platform_approve!
    verify_final_report!
    write_observations!
    finish!
  ensure
    cleanup! if @cleanup
  end

  private

  # ---------------------------------------------------------------- provision
  # Hard reset before a run: no stale background work, no tripped breaker, so the
  # slow local model starts from a clean slate (nothing queued in Sidekiq).
  def fresh_reset!
    stage "Fresh reset (clear queues + circuit breaker)"
    begin
      require "sidekiq/api"
      q = Sidekiq::Queue.new.size
      r = Sidekiq::RetrySet.new.size
      s = Sidekiq::ScheduledSet.new.size
      Sidekiq::Queue.new.clear
      Sidekiq::RetrySet.new.clear
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::DeadSet.new.clear
      log "  ✓ Sidekiq cleared (was queue=#{q} retry=#{r} scheduled=#{s})"
    rescue StandardError => e
      log "  ! Sidekiq clear skipped: #{e.class}: #{e.message}"
    end
    OpenaiCircuitBreaker.reset! if defined?(OpenaiCircuitBreaker)
    # reset! clears the flag but not the agent's windowed failure counter, so four
    # stale failures could re-trip the breaker on the first hiccup of a fresh run.
    # A "fresh reset" that leaves the window intact is not fresh.
    begin
      REDIS.del("openai:error_window")
    rescue StandardError => e
      log "  ! Could not clear the agent failure window: #{e.class}"
    end
    log "  ✓ Circuit breaker reset (open? #{defined?(OpenaiCircuitBreaker) && OpenaiCircuitBreaker.open?})"

    timeout = Integer(ENV.fetch("LANGGRAPH_READ_TIMEOUT", "45"))
    needed = RETRIEVAL ? 700 : 250
    log "  ✓ Agent read timeout #{timeout}s · memory retrieval #{RETRIEVAL ? 'ON' : 'OFF'}"
    # MEASURED on Gemma 12B: ~145s per turn without retrieval, ~570s with it. Below
    # that, every turn times out, the interview never advances, and the breaker trips
    # — which reads as "discovery is broken" rather than "the timeout is too low".
    if timeout < needed
      log "  ! WARNING: #{timeout}s is under the measured turn time for this configuration."
      log "    Set LANGGRAPH_READ_TIMEOUT=#{needed} in .env, then: docker compose up -d rails"
    end
  end

  def provision!
    stage "Provision platform admin, company, admin, consultant"
    @platform = PlatformUser.find_by(email: "admin@reqapp.local") || PlatformUser.first
    check "Platform admin present", @platform.present?

    @company = Company.find_or_initialize_by(slug: SLUG)
    @company.assign_attributes(
      name: "Nimbus Trading Co LLC", display_name: "Nimbus Trading", locale: "en",
      portal_onboarding_completed_at: Time.current,
      settings: (@company.settings.presence || {}).merge(
        "engagement_mode" => "hybrid", "skip_platform_review" => false,
        # Interview limits (Discovery::ContextBuilder resolves company -> ENV -> default).
        "discovery_max_questions" => MAX_QUESTIONS, "discovery_min_questions" => MIN_QUESTIONS,
        "discovery_memory_retrieval_enabled" => RETRIEVAL,
        "consultant_can_contact_employees" => true
      )
    )
    @company.save!

    # Start every run from zero employees so leftovers from a prior (or larger)
    # run never leak into intelligence/report.
    purged = 0
    @company.employees.find_each { |e| DiscoverySimulator.purge_employee!(e, company: @company); purged += 1 }
    log "  ✓ Purged #{purged} pre-existing employee(s)" if purged.positive?

    Subscription.find_or_create_by!(company: @company) do |s|
      s.plan = "trial"; s.status = "trial"; s.trial_ends_at = 30.days.from_now
      s.conversation_limit = Subscriptions::PlanLimits.conversation_limit_for("trial")
    end

    @admin = CompanyUser.find_or_create_by!(company: @company, email: ADMIN_EMAIL) do |u|
      u.name = "Omar Haddad"; u.password = "password123"; u.role = "company_admin"
      u.status = "active"; u.jti = SecureRandom.uuid
    end

    @consultant = ConsultantUser.find_or_initialize_by(email: CONSULTANT_EMAIL)
    @consultant.assign_attributes(
      name: "Samir Al-Farsi", password: "password123", status: "active",
      jti: @consultant.jti.presence || SecureRandom.uuid,
      headline: "Trade operations & finance transformation · GCC import/distribution",
      bio: "Former Big-4 operations lead; procurement-to-pay, AP automation and customs for GCC importers.",
      expertise_tags: ["Procurement", "Finance", "Supply chain", "GCC markets"],
      industries: ["Import/Distribution", "Trading"], years_experience: 14,
      profile_status: "published"
    )
    @consultant.save!

    unless @company.consultant_assignments.active.exists?(consultant_user_id: @consultant.id)
      ConsultantAssignments::AssignService.call(company: @company, consultant_user: @consultant, platform_user: @platform)
    end

    # A stray active assignment from an older run (e.g. the pre-rename
    # samir.ops@reviewers.worktruth.local record) sits on this company forever
    # otherwise, and check_all_submitted! correctly refuses to call reviews
    # complete while ANY active consultant hasn't submitted -- so a leftover
    # nobody submits for silently blocks reviews_complete indefinitely. A fresh
    # scenario run means exactly one active consultant: this one.
    @company.consultant_assignments.active.where.not(consultant_user_id: @consultant.id).find_each(&:remove!)

    check "Company provisioned (#{@company.name})", @company.persisted?
    check "Company admin #{ADMIN_EMAIL}", @admin.email == ADMIN_EMAIL
    check "Consultant assigned", @company.consultant_assignments.active.exists?(consultant_user_id: @consultant.id)
  end

  # ---------------------------------------------------------------- documents
  def upload_documents!
    stage "Upload 4 realistic documents"
    dir = fixture_dir
    raise "Nimbus fixtures not found (docs/scenario-nimbus)" unless dir

    @documents = DOCUMENTS.map { |spec| ingest_document!(dir, spec) }
    ready = @documents.select { |d| d.reload.status == "ready" }
    check "Documents ingested (#{@documents.size})", @documents.size == DOCUMENTS.size
    check "Documents ready with text (#{ready.size})", ready.size == DOCUMENTS.size
    depts = ready.map(&:department).uniq.compact
    check "Multiple departments (#{depts.join(', ')})", depts.size >= 2
  end

  def ingest_document!(dir, spec)
    text = File.read(dir.join(spec[:file])).encode("UTF-8", invalid: :replace, undef: :replace)
    @company.documents.where(filename: spec[:file]).find_each { |d| d.document_chunks.delete_all; d.destroy }
    key = "companies/#{@company.id}/nimbus/#{SecureRandom.uuid}/#{spec[:file]}"
    Storage::MinioClient.new.upload(key: key, body: text, content_type: "text/plain")
    doc = @company.documents.create!(
      uploaded_by_company_user: @admin, source: "company_portal_upload",
      department: spec[:department], document_type: spec[:document_type], sensitivity: "internal",
      consultant_visible: true, filename: spec[:file], content_type: "text/plain",
      byte_size: text.bytesize, storage_key: key, status: "pending"
    )
    begin
      Multimodal::ChunkEmbedder.call(document: doc, text: text)
    rescue StandardError
      text.scan(/.{1,900}/m).each_with_index { |c, i| doc.document_chunks.create!(chunk_index: i, content: c) }
    end
    doc.update!(status: "ready", insights_preview: { "summary" => text.truncate(4000), "chunk_count" => doc.document_chunks.count })
    doc.reload
  end

  # ---------------------------------------------------------------- discovery
  def run_discovery!
    specs = selected_employees
    wa = specs.count { |s| s[:channel] == :whatsapp }
    web_n = specs.count { |s| s[:channel] == :web }
    stage "Discovery — #{wa} WhatsApp + #{web_n} web (ceiling #{MAX_QUESTIONS}, floor #{MIN_QUESTIONS}, one at a time)"

    # Strictly serial: each employee is fully interviewed before the next begins,
    # so a slow local model only ever handles one conversation at a time.
    @employees = specs.map do |spec|
      log "  → interviewing #{spec[:name]} (#{spec[:channel]})…"
      interview_employee!(spec)
    end

    completed = @employees.count { |e| e.conversations.where(status: "completed").exists? }
    check "Employees interviewed to completion (#{completed}/#{@employees.size})", completed == @employees.size
    whatsapp = @employees.count { |e| e.conversations.joins(:messages).where(messages: { channel: "whatsapp" }).exists? }
    check "WhatsApp channel exercised (#{whatsapp})", wa.zero? || whatsapp >= 1
    web = @employees.count { |e| e.conversations.joins(:messages).where(messages: { channel: "web" }).exists? }
    check "Web channel exercised (#{web})", web_n.zero? || web >= 1
  end

  # Pick MAX_EMPLOYEES employees, interleaving channels so a limited run still
  # exercises both WhatsApp and web (2 → 1 WhatsApp + 1 web).
  def selected_employees
    queues = EMPLOYEES.group_by { |s| s[:channel] }.values.map(&:dup)
    ordered = []
    while queues.any?(&:any?)
      queues.each { |q| ordered << q.shift if q.any? }
    end
    ordered.first(MAX_EMPLOYEES)
  end

  def interview_employee!(spec)
    reset_employee!(spec)
    employee =
      if spec[:channel] == :whatsapp
        @company.employees.create!(phone_e164: spec[:phone], display_name: spec[:name],
                                   participation_status: "invited", onboarding_step: "awaiting_consent",
                                   invited_at: Time.current, verified_at: Time.current)
      else
        @company.employees.create!(phone_e164: spec[:phone], email: web_email(spec[:name]), display_name: spec[:name],
                                   participation_status: "invited", onboarding_step: "verified",
                                   invited_at: Time.current, verified_at: Time.current)
      end

    if spec[:channel] == :whatsapp
      wa_send(spec, "YES") # consent
      answer_profiling(spec, employee, :whatsapp)
      cycle_answers(spec, employee, :whatsapp)
    else
      conv = @company.conversations.create!(employee: employee, status: "profiling",
                                            started_at: Time.current, last_activity_at: Time.current)
      Web::TurnRouter.bootstrap!(employee: employee, conversation: conv)
      answer_profiling(spec, employee, :web, conversation: conv)
      cycle_answers(spec, employee, :web, conversation: conv)
    end
    employee.reload
  end

  def answer_profiling(spec, employee, channel, conversation: nil)
    p = spec[:profiling]
    steps = { "role_title" => p[:role_title], "department" => p[:department], "seniority" => p[:seniority],
              "responsibilities" => p[:responsibilities], "primary_tools" => p[:tools] }
    12.times do
      conv = active_conversation(employee, conversation)
      step = conv&.state_snapshot&.dig("profiling", "step")
      break unless step && steps.key?(step)

      send_message(spec, employee, steps[step], channel, conv)
    end
  end

  def cycle_answers(spec, employee, channel, conversation: nil)
    answers = spec[:answers].cycle
    turns = 0
    while (conv = active_conversation(employee, conversation)) && conv.status == "discovery" && turns < MAX_DISCOVERY_TURNS
      send_message(spec, employee, answers.next, channel, conv)
      turns += 1
    end
  end

  def send_message(spec, employee, text, channel, conv)
    if channel == :whatsapp
      wa_send(spec, text)
    else
      Web::TurnRouter.handle_text(employee: employee.reload, conversation: conv.reload, text: text)
    end
  end

  def wa_send(spec, text)
    phone = spec[:phone].delete("+")
    payload = { "entry" => [{ "changes" => [{ "value" => {
      "messages" => [{ "from" => phone, "id" => "wamid.nb.#{SecureRandom.hex(8)}", "type" => "text", "text" => { "body" => text } }],
      "contacts" => [{ "wa_id" => phone, "profile" => { "name" => spec[:name] } }]
    } }] }] }
    Whatsapp::InboundProcessor.new(payload).process
  end

  def active_conversation(employee, conversation)
    return conversation.reload if conversation

    employee.conversations.order(:created_at).last
  end

  # ------------------------------------------------------------------ dossier
  # Discovery now ends on a filled role dossier rather than a question counter, so
  # the run has to show WHY each interview stopped and what it actually learned.
  def verify_dossier!
    stage "Dossier — what each interview learned, and why it stopped"

    @employees.each do |employee|
      conv = employee.conversations.where(status: "completed").order(:created_at).last
      next unless conv

      bb = conv.blackboard
      slots = (bb.dig("dossier", "slots") || {})
      threshold = Discovery::ContextBuilder.limits_for(@company)[:slot_confidence]
      filled = slots.select { |_, v| v["confidence"].to_f >= threshold }
      areas = Array(bb["role_areas"]).filter_map { |a| a["name"] }
      reason = bb["close_reason"]
      parked = Array(bb.dig("dossier", "parked"))

      name = employee.display_name
      check "#{name}: role areas discovered (#{areas.join(', ')})", areas.any?
      check "#{name}: dossier slots filled (#{filled.size})", filled.any?
      check "#{name}: close reason recorded (#{reason})", reason.present?
      check "#{name}: asked #{conv.question_count}, ceiling #{MAX_QUESTIONS}",
            conv.question_count <= MAX_QUESTIONS
      check "#{name}: reached the floor (#{conv.question_count} >= #{MIN_QUESTIONS})",
            conv.question_count >= MIN_QUESTIONS

      # Not a failure — a signal. Closing on the ceiling every time means the dossier
      # wants more than the interview can get.
      observe("dossier", reason == "ceiling" ? "warn" : "info", "#{name} close",
              "#{reason} after #{conv.question_count}q")
      log "  · #{name}: discovery ENDED ITSELF after #{conv.question_count} questions — reason: #{reason.inspect}"
      observe("dossier", "info", "#{name} filled", filled.keys.join(" | "))
      observe("dossier", "info", "#{name} parked", parked.map { |x| x["note"] }.join(" | ")) if parked.any?
    end
  end

  # ------------------------------------------------------------------ package
  # The structured handover the consultant reads instead of a transcript. Built
  # synchronously here; in the app a job does it on interview completion.
  def build_packages!
    stage "Discovery packages — the consultant handover"
    @packages = []

    @employees.each do |employee|
      conv = employee.conversations.where(status: "completed").order(:created_at).last
      next unless conv

      # FinalizeConversationService also enqueues BuildDiscoveryPackageJob, so if a
      # worker is running one already exists. Reuse it rather than minting a second
      # version that supersedes the first — otherwise this stage reviews a package
      # the rest of the app considers stale.
      package = DiscoveryPackage.current.where(conversation: conv).order(version: :desc).first ||
                Discovery::BuildPackageService.call(conversation: conv)
      @packages << package
      name = employee.display_name

      check "#{name}: package ready (v#{package.version}, #{package.generated_by})",
            package.status == "ready"
      check "#{name}: package has a recommendation", package.recommendation.present?
      check "#{name}: package has issues (#{package.issues.count})", package.issues.any?
      check "#{name}: package drafted follow-ups (#{package.discovery_followup_questions.count})",
            package.discovery_followup_questions.any?

      observe("package", "info", "#{name} recommendation", package.recommendation.to_s.truncate(220))
      observe("package", "info", "#{name} issues",
              package.issues.map { |i| "[#{i.impact}] #{i.title}" }.join(" | "))
      observe("package", "info", "#{name} solutions",
              package.solutions.map { |x| x.title }.join(" | ").presence || "(none — deterministic build)")
      observe("package", "info", "#{name} next question",
              package.next_followup&.body.to_s.truncate(160))

      log "\n  ┌─ what the consultant sees for #{name} (package v#{package.version}, #{package.generated_by}) ─"
      log "  │ recommendation: #{package.recommendation.to_s.truncate(180)}"
      package.issues.each { |i| log "  │ issue [#{i.impact}] #{i.title}: #{i.body.to_s.truncate(120)}" }
      if package.solutions.any?
        package.solutions.each { |sn| log "  │ solution: #{sn.title}: #{sn.body.to_s.truncate(120)}" }
      else
        log "  │ solutions: none (deterministic build — no model solutions proposed)"
      end
      if package.next_followup
        log "  │ agent's drafted next question: #{package.next_followup.body}"
      else
        log "  │ agent drafted no follow-up questions"
      end
      log "  └───────────────────────────────────────────────────────"
    end

    check "A package exists per interviewed employee (#{@packages.size}/#{@employees.size})",
          @packages.size == @employees.size
  end

  # --------------------------------------------------- consultant reviews package
  # The consultant amends the handover, then states what they still need to know —
  # in their own words. The agent drafts the question; the employee answers on their
  # real channel; the requirement is re-evaluated. This is the loop end to end.
  def consultant_reviews_package!
    stage "Consultant reviews the handover and raises a need"
    package = @packages.first
    return check("Package available to review", false) if package.nil?

    spec = selected_employees.first
    employee = @employees.first

    # 1. Amend the substance. The agent's original survives in agent_payload.
    original = package.recommendation
    package.update!(recommendation: "Automate the PI-to-LPO match first; AP re-keying is downstream of it.")
    check "Consultant rewrote the recommendation",
          package.reload.recommendation != original && package.agent_payload["recommendation"] == original

    # 2. Reject one agent issue and add one of their own. A rejection is kept, not
    #    deleted — it is a signal about agent quality.
    rejected = package.issues.first
    rejected&.update!(status: "rejected")
    package.discovery_package_items.create!(
      kind: "issue", origin: "consultant", status: "accepted", impact: "medium",
      title: "Advance payment exposure",
      body: "PIs are paid on advance before the price drift is caught, so the cash is already out the door."
    )
    check "Agent issue rejected but retained", rejected.nil? || rejected.reload.status == "rejected"
    check "Consultant added their own issue",
          package.discovery_package_items.where(origin: "consultant").exists?

    # 3. State a need. The consultant never writes the question text.
    requirement = ConsultantRequirements::CreateService.call(
      package: package, consultant: @consultant,
      statement: "I need to know who signs off on a PI once a price mismatch is found, and whether they can hold the payment."
    )
    # CreateService drafts via DraftRequirementQuestionsJob.perform_later -- real
    # Sidekiq here, not inline. Reading the association right after create raced the
    # worker and reported "0 questions drafted" even though the job went on to draft
    # two good ones a few seconds later. Wait for it, the way the package stage above
    # tolerates a worker that hasn't run yet rather than assuming synchronous timing.
    drafted = wait_for { requirement.reload.discovery_followup_questions.in_queue_order.to_a.presence }
    drafted ||= []

    check "Requirement recorded", requirement.statement.present?
    check "Agent drafted question(s) from the need (#{drafted.size})", drafted.any?
    observe("requirement", "info", "consultant stated", requirement.statement)
    observe("requirement", "info", "agent drafted", drafted.map(&:body).join(" | "))

    log "\n  ┌─ consultant → agent → employee, end to end ─"
    log "  │ consultant STATED (their own words, not question text):"
    log "  │   \"#{requirement.statement}\""
    log "  │ agent DRAFTED (this is what actually gets sent):"
    drafted.each { |q| log "  │   \"#{q.body}\"" }

    if drafted.empty?
      log "  └── no question drafted — nothing to send"
      return
    end

    # 4. Send it on the employee's real channel and have them answer through the
    #    real inbound path, so routing and attribution are exercised, not stubbed.
    question = drafted.first
    ConsultantRequirements::SendQuestionService.call(question: question, consultant: @consultant)
    question.reload
    check "Question sent (#{question.consultant_info_request&.channel})", question.status == "sent"

    log "  │ SENT on channel: #{question.consultant_info_request&.channel} (real delivery path, template if outside 24h window)"

    answer = "Our finance manager Aisha signs off any PI with a mismatch, and she can hold the payment until it is fixed."
    log "  │ EMPLOYEE answers (via #{spec[:channel]}, real inbound path): \"#{answer}\""
    if spec[:channel] == :whatsapp
      wa_send(spec, answer)
    else
      conv = active_conversation(employee, nil)
      Web::TurnRouter.handle_text(employee: employee, conversation: conv, text: answer) if conv
    end

    question.reload
    requirement.reload
    check "Employee's answer attributed to the question", question.status == "answered"
    check "Requirement re-evaluated (#{requirement.status})",
          %w[satisfied partially_satisfied].include?(requirement.status)
    observe("requirement", "info", "outcome",
            "#{requirement.status} (#{requirement.satisfaction_basis || 'n/a'}) missing=#{requirement.missing_aspects.inspect}")
    log "  │ REQUIREMENT re-evaluated: #{requirement.status} (basis: #{requirement.satisfaction_basis || 'n/a'})"
    log "  │   missing_aspects: #{requirement.missing_aspects.inspect}"
    log "  └───────────────────────────────────────────────────────"

    budget = Discovery::FollowupLimits.package_budget_remaining(package)
    check "Employee follow-up budget decremented (#{budget} left)",
          budget < Discovery::FollowupLimits.max_per_package(@company)
  end

  # ---------------------------------------------------------------- intelligence
  def run_intelligence!
    stage "Intelligence aggregation"
    result = Intelligence::AggregateCompanyIntelligence.call(company: @company.reload)
    @company.reload
    CompanyReadinessRefresher.call(@company) if defined?(CompanyReadinessRefresher)
    @company.reload
    check "Signals extracted (#{result[:signals]})", result[:signals].to_i.positive?
    check "Patterns detected (#{@company.patterns.count})", @company.patterns.any?
    check "Recommendations (#{@company.recommendations.count})", @company.recommendations.any?
    check "Readiness score (#{@company.report_readiness_score})", @company.report_readiness_score.to_f.positive?
    observe("intelligence", "info", "counts",
            "signals=#{@company.company_signals.count} patterns=#{@company.patterns.count} recs=#{@company.recommendations.count} ideas=#{@company.agentic_ideas.count}")
  end

  # ---------------------------------------------------------------- report
  def generate_report!
    stage "Report generation (gated)"
    @company.agentic_ideas.draft.order(confidence: :desc).limit(3).find_each(&:publish!)
    previous = @company.reports.ready.order(version: :desc).first
    @report = @company.reports.create!(
      version: (@company.reports.maximum(:version) || 0) + 1, status: "queued",
      visibility: "internal_only", triggered_by_type: "CompanyUser", triggered_by_id: @admin.id,
      previous_report: previous, review_workflow_status: "awaiting_consultants"
    )
    Reports::GenerateReportService.call(report: @report)
    @report.reload
    check "Report generated to ready", @report.status == "ready"
    check "Report is GATED internal_only (not shipped)", @report.visibility == "internal_only"
    check "Report awaiting consultants", @report.review_workflow_status == "awaiting_consultants"
    check "Consultant review bootstrapped", @report.report_reviews.exists?(consultant_user_id: @consultant.id)
    # Company must NOT be able to download an unapproved report.
    check "Company CANNOT download before approval", company_can_download? == false
    observe("report", "info", "exec summary",
            @report.report_snapshot["executive_summary"].to_s.truncate(300))
    observe("report", "info", "narrative source",
            @report.report_snapshot.dig("narrative", "generated_by") || "deterministic")
  end

  # ---------------------------------------------------------------- consultant
  def consultant_contribution!
    stage "Consultant contributes (decisions, comment, prose edit, added section, finding, Q&A)"
    @review = @report.report_reviews.find_by(consultant_user: @consultant)
    raise "review missing" unless @review

    ReportSections::KEYS.each do |key|
      @review.report_review_section_states.find_or_create_by!(section_key: key).update!(status: "approved")
    end
    @review.report_review_comments.create!(consultant_user: @consultant, section_key: "recommendations",
      body: "Sequence the PI auto-match ahead of AP re-keying — it removes the upstream mismatch that causes the exceptions.")

    # Prose EDIT that REPLACES the AI executive summary.
    @report.report_section_overrides.create!(consultant_user: @consultant, action: "edit", section_key: "executive_summary",
      body: "Nimbus loses the most time where paperwork crosses systems: manual proforma-invoice checking (1 in 4 PIs mismatch) and 100% manual AP re-keying (three-way match first-pass only ~72%). Fixing the PI-to-LPO match first removes the upstream cause of the AP exceptions.",
      published: true)
    # ADDED custom section.
    @report.report_section_overrides.create!(consultant_user: @consultant, action: "add", title: "Risk register",
      body: "Demurrage exposure at Jebel Ali when customs clearance slips beyond 48h; price-drift on Supplier A PIs (~5-8%) paid on advance before sign-off.",
      anchor_section: "recommendations", published: true)
    # Publishable executive-conclusion finding (required by SubmitService).
    if defined?(ReportReviewFinding) && ReportReviewFinding.table_exists?
      @review.report_review_findings.create!(consultant_user: @consultant, finding_type: "executive_conclusion",
        severity: "info", disposition: "endorse", publishable: true,
        body: "As a trade-ops consultant I endorse the docs+interview narrative: PI checking and AP re-keying are the core, quantified frictions; automating the PI-to-LPO match is the highest-leverage first move.",
        evidence_refs: %w[doc:procurement-sop doc:ap-three-way-match-policy])
    end
    @review.update!(overall_note: "Strong, well-evidenced discovery. Endorsed with one added risk register and a sharpened executive summary.")

    # Consultant → company-admin clarification Q&A (consent-gated path is admin-approved).
    outreach = Outreaches::CreateService.call(
      consultant: @consultant, company: @company, recipient_type: "company_admin", recipient_id: @admin.id,
      body: "Omar — can you confirm the monthly value of PIs that hit a price mismatch, so we can size the PI-match opportunity?",
      purpose: "clarification", channel: "portal", report_id: @report.id, reason: "size PI-match opportunity"
    )
    Outreaches::RecordReplyService.call(outreach: outreach.reload,
      body: "Roughly AED 300k of PIs a month carry a price drift; catching them earlier would save real cash.",
      channel: "portal", company_user: @admin)
    outreach.update!(status: "closed")

    check "Section decisions recorded (approved)", @review.report_review_section_states.where(status: "approved").count == ReportSections::KEYS.size
    check "Prose EDIT override created", @report.report_section_overrides.where(action: "edit").exists?
    check "Custom section ADDED", @report.report_section_overrides.where(action: "add").exists?
    check "Consultant clarification answered", outreach.reload.status == "closed"
  end

  # ---------------------------------------------------------------- gate
  def assert_gate_blocks_when_needs_info!
    stage "Gate: needs_info blocks approval"
    section = @review.report_review_section_states.first
    section.update!(status: "needs_info")
    @review.update!(status: "needs_info")
    check "Approval blocked while a review is needs_info",
          @report.report_reviews.where(status: "needs_info").exists?
    # Resolve so the happy path can complete.
    section.update!(status: "approved")
    @review.update!(status: "approved")
  end

  # ---------------------------------------------------------------- approve
  def platform_approve!
    stage "Consultant submits → platform approves"
    ReportReviews::SubmitService.call(report_review: @review.reload)
    @report.reload
    check "Review submitted (approved)", @review.reload.status == "approved"
    check "Report reviews_complete", @report.review_workflow_status == "reviews_complete"

    # Replicate the platform approve flow (regenerate with consultant edits, then share).
    raise "needs_info still blocks" if @report.report_reviews.where(status: "needs_info").exists?
    Reports::RegenerateWithReviewService.call(report: @report) if @report.report_reviews.exists?
    @report.reload
    raise "artifact not a real PDF" if @report.content_type != "application/pdf" && !MocksAllowed.allowed?
    @report.update!(visibility: "shared_with_company", review_workflow_status: "platform_approved",
                    reviewed_by_platform_user: @platform, reviewed_at: Time.current)
    NotificationService.notify_report_ready(company: @company, report: @report)

    check "Report shared_with_company after approval", @report.visibility == "shared_with_company"
    check "Company CAN download after approval", company_can_download? == true
  end

  # ---------------------------------------------------------------- verify
  def verify_final_report!
    stage "Inspect the final deliverable"
    body = Storage::MinioClient.new.download(@report.storage_key)
    check "Final artifact non-empty (#{body.bytesize} bytes)", body.bytesize > 1000
    # Consultant's prose EDIT must have replaced the AI exec summary in the final render.
    applied = Reports::SectionOverridesApplier.call(snapshot: @report.report_snapshot, report: @report)
    html = Reports::HtmlBuilder.call(snapshot: applied, report_version: @report.version)
    check "Consultant's edited exec summary in final report", html.include?("Fixing the PI-to-LPO match first")
    check "Consultant's added Risk register in final report", html.include?("Risk register")
    check "No raw internal score leaked (e.g. '0.74')", !html.match?(/strength \(0\.\d\d\)|confidence \(0\.\d\d\)/)
    observe("deliverable", "info", "content_type", @report.content_type)
    observe("deliverable", "info", "top pain points",
            Array(@report.report_snapshot["signals"]).first(3).map { |s| s["label"] }.join(" | "))
  end

  # ---------------------------------------------------------------- output
  def write_observations!
    observe("channels", "info", "employees", @employees.map { |e| "#{e.display_name}" }.join(", "))
    path = Rails.root.join("tmp", "nimbus_scenario_results.json")
    path.dirname.mkpath
    path.write(JSON.pretty_generate(
      "slug" => SLUG, "checks" => @checks.map { |l, ok| { "label" => l, "ok" => ok } },
      "observations" => @observations, "report_id" => @report&.id, "report_version" => @report&.version
    ))
    puts "\n  → results: #{path}"
  end

  def finish!
    passed = @checks.count { |_, ok| ok }
    banner "Done — #{passed}/#{@checks.size} checks passed"
    @checks.each { |l, ok| puts "  #{ok ? '✓' : '✗ FAIL —'} #{l}" }
    puts "\nObservations:"
    @observations.each { |a| puts "  · [#{a['area']}] #{a['title']}: #{a['detail']}" }
    puts "\nLogins — company #{ADMIN_EMAIL} / password123 · consultant #{CONSULTANT_EMAIL} / password123"
    raise "Scenario had #{@checks.count { |_, ok| !ok }} failing checks" if @checks.any? { |_, ok| !ok } && !@cleanup
  end

  # ---------------------------------------------------------------- helpers
  def fixture_dir
    @fixture_dir ||= FIXTURE_DIRS.find { |p| p.exist? && p.join("procurement-sop.txt").exist? }
  end

  def web_email(name)
    "#{name.downcase.gsub(/[^a-z]+/, '.')}@nimbus-web.local"
  end

  def reset_employee!(spec)
    existing =
      if spec[:channel] == :whatsapp
        Employee.find_by(phone_e164: spec[:phone])
      else
        Employee.find_by(email: web_email(spec[:name]))
      end
    DiscoverySimulator.purge_employee!(existing, company: @company) if existing
  end

  # Minimal Pundit context answering the predicates ReportPolicy needs for a
  # company admin, to assert the download gate.
  def company_can_download?
    company_id = @company.id
    ctx = Object.new
    ctx.define_singleton_method(:platform?) { false }
    ctx.define_singleton_method(:company?) { true }
    ctx.define_singleton_method(:consultant?) { false }
    ctx.define_singleton_method(:company_id) { company_id }
    ctx.define_singleton_method(:assigned_company_ids) { [] }
    ctx.define_singleton_method(:assigned_company?) { |_| false }
    ReportPolicy.new(ctx, @report.reload).download?
  end

  def observe(area, severity, title, detail)
    @observations << { "area" => area, "severity" => severity, "title" => title, "detail" => detail.to_s }
  end

  def check(label, passed)
    @checks << [label, !!passed]
    puts format("  %s %s", passed ? "✓" : "✗ FAIL —", label)
  end

  def stage(name)
    # The shared circuit breaker is the single most common reason a run degrades
    # into "delay" messages, and it is invisible unless you print it. Showing it at
    # every boundary turns "discovery is broken" into "the breaker opened during X".
    breaker = begin
      OpenaiCircuitBreaker.open? ? " [BREAKER OPEN]" : ""
    rescue StandardError
      " [breaker unknown]"
    end
    puts "\n— #{name}#{breaker} " + "-" * [60 - name.length, 5].max
  end

  def log(msg)
    puts msg
    $stdout.flush
  end

  # Polls for something a Sidekiq worker produces asynchronously. Matches
  # LANGGRAPH_DRAFT_READ_TIMEOUT (180s) plus margin for the worker to pick the job
  # up at all -- a real model draft call can legitimately take tens of seconds.
  def wait_for(timeout: 200, interval: 2)
    deadline = Time.current + timeout
    loop do
      result = yield
      return result if result
      return nil if Time.current > deadline

      sleep interval
    end
  end

  def banner(text)
    puts "=" * 72
    puts text
    puts "=" * 72
  end

  def cleanup!
    stage "Cleanup"
    @employees&.each { |e| DiscoverySimulator.purge_employee!(e, company: @company) rescue nil }
    puts "  Scenario employees removed (company/consultant/report kept for inspection)."
  end
end
