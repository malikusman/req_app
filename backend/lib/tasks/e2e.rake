# frozen_string_literal: true

namespace :e2e do
  desc "Provision a company user with an approved, fully-rendered report for the browser tests"
  task seed_report_reader: :environment do
    abort "Refusing to run in production" if Rails.env.production?

    email = ENV.fetch("E2E_EMAIL", "reader-e2e@mjadi.test")
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
    consultant = ConsultantUser.find_or_initialize_by(email: "reader-e2e-consultant@mjadi.test")
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

  desc "Provision a key user at the start of company onboarding, with one website proposal to confirm"
  task seed_onboarding: :environment do
    abort "Refusing to run in production" if Rails.env.production?

    email = ENV.fetch("E2E_ONBOARDING_EMAIL", "onboarding-e2e@mjadi.test")
    password = ENV.fetch("E2E_ONBOARDING_PASSWORD", "OnboardingE2E123!")
    website = "https://example-trading.ae/"

    company = Company.find_or_create_by!(slug: "onboarding-e2e") do |c|
      c.name = "Onboarding E2E Co"
      c.display_name = "Onboarding E2E Co"
      c.locale = "en"
    end
    # Access comes from the engagement, not a subscription (Doc 07 §1). Every run
    # starts from a first-time key user with nothing answered.
    company.subscription&.destroy!
    company.engagements.destroy_all
    company.company_systems.destroy_all
    company.profile_changes.delete_all
    company.update!(
      approval_status: "approved", website_url: website, portal_onboarding_completed_at: nil,
      questionnaire_answers: {}, questionnaire_step: 1, company_profile: {}, profile_provenance: {}
    )

    user = CompanyUser.find_or_initialize_by(email: email)
    user.assign_attributes(company: company, name: "Onboarding E2E Admin", role: "company_admin", status: "active",
                           password: password, onboarding_completed_at: nil)
    user.save!

    # Created directly rather than through Engagements::Create, so no invitation
    # is sent and no website is fetched.
    engagement = company.engagements.create!(
      status: "ONBOARDING", scope_type: "COMPANY", languages: %w[en], key_user: user,
      status_history: [{ "from" => nil, "to" => "ONBOARDING", "at" => Time.current.iso8601, "reason" => "e2e seed" }],
      prefill_status: "done", prefill_finished_at: Time.current
    )
    engagement.prefill_candidates.create!(
      company: company, target_field: "industry", value: "Wholesale distribution — tailoring materials",
      display_text: "Wholesaler of tailoring materials", confidence: "HIGH", source_url: website,
      evidence_excerpt: "one of the leading wholesalers of tailoring materials", website_url: website,
      prompt_version: "P01.v1", extracted_at: Time.current
    )

    puts "Seeded #{email} / #{password} (company ##{company.id}, engagement ##{engagement.id}, onboarding reset)"
  end

  desc "Provision a key user at the start of their conversation with leadership, with scripted replies and one manager"
  task seed_key_person: :environment do
    abort "Refusing to run in production" if Rails.env.production?

    email = ENV.fetch("E2E_KEY_PERSON_EMAIL", "key-person-e2e@mjadi.test")
    password = ENV.fetch("E2E_KEY_PERSON_PASSWORD", "KeyPersonE2E123!")
    manager_link = ENV.fetch("E2E_MANAGER_LINK", "e2e-manager-link")

    company = Company.find_or_create_by!(slug: "key-person-e2e") do |c|
      c.name = "Key Person E2E Co"
      c.display_name = "Key Person E2E Co"
      c.locale = "en"
    end
    company.subscription&.destroy!
    company.engagements.destroy_all
    company.documents.leadership.destroy_all
    # No model in the browser test: the conversation runs on scripted replies
    # (KeyPerson::ScriptedClient), which only exists outside production.
    company.update!(
      approval_status: "approved", portal_onboarding_completed_at: Time.current,
      company_profile: { "industry" => "Wholesale distribution", "org_departments" => %w[Sales Procurement] },
      settings: Company::DEFAULT_SETTINGS.merge("key_person_scripted_replies" => true)
    )

    user = CompanyUser.find_or_initialize_by(email: email)
    user.assign_attributes(company: company, name: "Layla Haddad", role: "company_admin", status: "active",
                           password: password, onboarding_completed_at: Time.current, job_title: "CEO")
    user.save!

    engagement = company.engagements.create!(
      status: "KEY_PERSON_DISCOVERY", scope_type: "COMPANY", languages: %w[en], key_user: user,
      onboarding_submitted_at: Time.current, confidentiality_acknowledged_at: Time.current,
      planned_departments: [{ "name" => "Sales", "count" => "UNKNOWN" }, { "name" => "Procurement", "count" => 2 }],
      status_history: [{ "from" => nil, "to" => "KEY_PERSON_DISCOVERY", "at" => Time.current.iso8601, "reason" => "e2e seed" }]
    )
    manager = engagement.participants.create!(company: company, participant_type: "KEY_PERSON", name: "Rania Saleh",
                                              role_title: "Head of Sales", scope: "Sales", email: "rania@key-person-e2e.test")
    KeyPerson::Kickoff.call(engagement)
    # A known link for the manager, so the browser test can open it.
    manager.reload.update!(access_token_digest: KeyPerson::Invite.digest(manager_link),
                           access_token_expires_at: 14.days.from_now)

    puts "Seeded #{email} / #{password} (company ##{company.id}, engagement ##{engagement.id}); " \
         "manager link /leadership/#{manager_link}"
  end

  # Stage 1 pricing in the browser (e2e/pricing.spec.ts): an engagement in
  # STAGE_1_PRICING with its quote proposed and explained (scripted P24), which
  # the demo administrator and consultant can see.
  desc "Seed an engagement waiting on its Stage 1 quote, for e2e/pricing.spec.ts"
  task seed_pricing: :environment do
    abort "Refusing to run in production" if Rails.env.production?

    email = ENV.fetch("E2E_PRICING_EMAIL", "pricing-e2e@mjadi.test")
    password = ENV.fetch("E2E_PRICING_PASSWORD", "PricingE2E123!")
    Pricing::Defaults.ensure!

    company = Company.find_or_create_by!(slug: "pricing-e2e") do |c|
      c.name = "Pricing E2E Co"
      c.display_name = "Pricing E2E Co"
      c.locale = "en"
    end
    company.subscription&.destroy!
    AiRun.where(engagement_id: company.engagements.select(:id)).delete_all
    company.engagements.destroy_all
    company.employees.destroy_all
    company.update!(
      approval_status: "approved", portal_onboarding_completed_at: Time.current,
      company_profile: { "industry" => "wholesale_distribution", "country" => "United Arab Emirates",
                         "locations" => ["Dubai"] },
      settings: Company::DEFAULT_SETTINGS.merge("pricing_scripted_replies" => true)
    )

    user = CompanyUser.find_or_initialize_by(email: email)
    user.assign_attributes(company: company, name: "Huda Saleh", role: "company_admin", status: "active",
                           password: password, onboarding_completed_at: Time.current, job_title: "General Manager")
    user.save!

    consultant = ConsultantUser.find_by(email: "consultant@reqapp.local")
    if consultant
      assignment = ConsultantAssignment.find_or_initialize_by(company: company, consultant_user: consultant)
      assignment.assigned_by_platform_user ||= PlatformUser.find_by(email: "admin@reqapp.local")
      assignment.assigned_at ||= Time.current
      assignment.update!(status: "active")
    end

    engagement = company.engagements.create!(
      status: "STAGE_1_PRICING", scope_type: "COMPANY", languages: %w[en ar], key_user: user, lead_consultant: consultant,
      onboarding_submitted_at: Time.current, confidentiality_acknowledged_at: Time.current,
      planned_departments: [{ "name" => "Sales", "count" => 2 }, { "name" => "Procurement", "count" => 1 }],
      status_history: [{ "from" => nil, "to" => "STAGE_1_PRICING", "at" => Time.current.iso8601, "reason" => "e2e seed" }]
    )
    quote = Pricing::ProposeStage1.call(engagement, reason: "e2e seed").quote
    Pricing::Explainer.call(quote)

    puts "Seeded #{email} / #{password} (company ##{company.id}, engagement ##{engagement.id}, " \
         "quote ##{quote.id}, explained by #{quote.reload.explanation_source})"
  end

  desc "Seed an engagement with scripted synthesis to review, for e2e/synthesis.spec.ts"
  task seed_synthesis: :environment do
    abort "Refusing to run in production" if Rails.env.production?

    email = ENV.fetch("E2E_SYNTHESIS_EMAIL", "synthesis-e2e@mjadi.test")
    password = ENV.fetch("E2E_SYNTHESIS_PASSWORD", "SynthesisE2E123!")

    company = Company.find_or_create_by!(slug: "synthesis-e2e") do |c|
      c.name = "Synthesis E2E Co"
      c.display_name = "Synthesis E2E Co"
      c.locale = "en"
    end
    engagement_ids = company.engagements.pluck(:id)
    # Synthesis keeps everything; clear this company's so the seed starts clean.
    SynthesisDecision.where(engagement_id: engagement_ids).delete_all
    EffortNormalization.where(engagement_id: engagement_ids).delete_all
    SynthesisClusterMember.where(synthesis_cluster_id: SynthesisCluster.where(engagement_id: engagement_ids).select(:id)).delete_all
    [SynthesisCluster, ProcessRelationship, ConsultancyOpportunity, RootCause, ManagementValidation].each do |model|
      model.where(engagement_id: engagement_ids).delete_all
    end
    AiRun.where(engagement_id: engagement_ids).delete_all
    SynthesisRun.where(engagement_id: engagement_ids).delete_all
    company.subscription&.destroy!
    company.engagements.destroy_all
    company.findings.delete_all
    company.employees.destroy_all
    company.update!(
      approval_status: "approved", portal_onboarding_completed_at: Time.current,
      company_profile: { "industry" => "wholesale_distribution", "country" => "United Arab Emirates",
                         "org_departments" => %w[Sales Procurement Finance] },
      settings: Company::DEFAULT_SETTINGS.merge("synthesis_scripted_replies" => true)
    )

    user = CompanyUser.find_or_initialize_by(email: email)
    user.assign_attributes(company: company, name: "Huda Saleh", role: "company_admin", status: "active",
                           password: password, onboarding_completed_at: Time.current, job_title: "General Manager")
    user.save!

    consultant = ConsultantUser.find_by(email: "consultant@reqapp.local")
    if consultant
      assignment = ConsultantAssignment.find_or_initialize_by(company: company, consultant_user: consultant)
      assignment.assigned_by_platform_user ||= PlatformUser.find_by(email: "admin@reqapp.local")
      assignment.assigned_at ||= Time.current
      assignment.update!(status: "active")
    end

    engagement = company.engagements.create!(
      status: "STAGE_1_ACTIVE", scope_type: "COMPANY", languages: %w[en], key_user: user, lead_consultant: consultant,
      onboarding_submitted_at: Time.current, confidentiality_acknowledged_at: Time.current,
      planned_departments: [{ "name" => "Sales", "count" => 3 }, { "name" => "Procurement", "count" => 1 },
                            { "name" => "Finance", "count" => 1 }],
      status_history: [{ "from" => nil, "to" => "STAGE_1_ACTIVE", "at" => Time.current.iso8601, "reason" => "e2e seed" }]
    )

    quote_work = "Check stock and the price list, fill the quotation template and email it to the customer"
    [["Sales Coordinator", "Sales", [150, 200]], ["Sales Coordinator", "Sales", [120, 160]],
     ["Sales Coordinator", "Sales", [100, 140]], ["Buyer", "Procurement", [60, 90]]].each_with_index do |(role, dept, hours), i|
      employee = company.employees.create!(display_name: "E2E Person #{i + 1}", role_title: role, department: dept,
                                           phone_e164: "+97150990#{format('%04d', i)}", participation_status: "completed",
                                           onboarding_step: "verified", preferred_language: "en")
      company.findings.create!(
        employee: employee, source_key: "synthesis-e2e-#{i}", department: dept, role_title: role,
        area: role == "Buyer" ? "Supplier prices" : "Preparing quotes",
        title: role == "Buyer" ? "Entering supplier prices" : "Preparing quotes",
        what_happens_now: role == "Buyer" ? "Key supplier price sheets into the ERP every week" : quote_work,
        friction: role == "Buyer" ? "Every supplier sends a different format" : "The price list is often out of date",
        annual_hours_min: hours.first, annual_hours_max: hours.last, status: "draft"
      )
    end

    owner = engagement.participants.create!(company: company, participant_type: "KEY_PERSON", name: "Huda Saleh",
                                            persona: "CEO_OWNER_MD", participation_status: "COMPLETED")
    session = ConversationSession.create!(company: company, engagement: engagement, participant: owner,
                                          session_type: "KEY_PERSON", state: "COMPLETE")
    context = ManagementDiscoveryContext.create!(
      company: company, engagement: engagement, participant: owner, session: session, status: "COMPLETE",
      schema_version: "MDC.v1", persona: "CEO_OWNER_MD",
      content: { "concerns" => [{ "text" => "Quotes take too long to reach customers", "evidence" => ["t2"] }] },
      consultant_private: { "political_context" => { "decision_makers" => [{ "note" => "SENTINEL-POLITICS" }] } }
    )
    context.strategic_findings.create!(company: company, engagement: engagement, category: "PROCESS", scope: "DEPARTMENT",
                                       statement: "Quotes take too long to reach customers", source_basis: "MANAGEMENT_STATEMENT",
                                       fact_status: "REPORTED", management_importance: "HIGH", evidence: ["t2"])

    run = SynthesisRun.create!(company: company, engagement: engagement, version: 1, trigger: "MANUAL",
                               requested_at: Time.current)
    Synthesis::Run.call(run)
    puts "Seeded #{email} / #{password} (company ##{company.id}, engagement ##{engagement.id}, synthesis " \
         "#{run.reload.status}: #{SynthesisCluster.current.where(engagement: engagement).count} cluster(s), " \
         "#{ConsultancyOpportunity.current.where(engagement: engagement).count} opportunity(ies))"
  end
end
