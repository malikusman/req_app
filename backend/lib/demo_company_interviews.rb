# frozen_string_literal: true

require_relative "discovery_simulator"

# Interviews a whole demo company through the real production path, so the report
# can be tested against findings the current interview engine actually produced.
#
# Each employee answers from a private fact sheet, via a model, rather than from a
# script — a script answers the question it expected, not the one it was asked, and
# that produced findings like "twice a week, 8 days each" that no real person said.
#
# The fact sheets are built to exercise the report: two procurement officers who
# both chase purchase orders (a merge for the consultant), a role held by one person
# (withheld until reviewed), waiting time (never counted), and a turnaround time
# given before the effort (never recorded as effort).
#
#   rails demo:company_interviews                 # all seven
#   ONLY=shiv,ravi rails demo:company_interviews  # some
class DemoCompanyInterviews
  SLUG = "gulf-trading-demo"

  COMPANY = {
    name: "Gulf Trading Co.",
    locale: "en",
    company_profile: {
      "industry" => "Wholesale distribution", "size_band" => "51-200", "region" => "UAE",
      "business_goals" => ["Grow without adding back-office headcount", "Faster month-end close"],
      "org_departments" => %w[Procurement Finance Operations Sales HR]
    },
    settings: {
      "allow_early_report" => true, "discovery_profiling_enabled" => true,
      "discovery_multi_agent_enabled" => true, "discovery_memory_retrieval_enabled" => true
    }
  }.freeze

  STYLE = "Friendly and cooperative. Two to four sentences per answer."

  PEOPLE = [
    {
      key: "shiv", phone: "+14155559911", name: "Shiv Menon", style: STYLE,
      profiling: { role_title: "Procurement Officer", department: "Procurement",
                   seniority: "I'm an individual contributor",
                   responsibilities: "Supplier price updates, purchase orders and supplier follow-up",
                   tools: "NAV, Excel and WhatsApp" },
      facts: <<~FACTS
        - Supplier price updates: every morning you open the price sheets 5 or 6 suppliers email,
          and re-key each item into NAV by hand. It takes forty minutes to an hour. Each sheet has a
          different layout, so codes get mismatched and wrong prices reach customers about twice a month.
        - Purchase orders: you raise about 15 POs a week in NAV, then chase suppliers for order
          confirmation on WhatsApp and email. Chasing is 10 to 15 minutes per PO, and you often wait
          two or three days for a reply.
        - AI: you sometimes use ChatGPT to tidy up supplier emails. Nothing official.
        - With more time you'd find new suppliers and negotiate better terms on the top lines.
      FACTS
    },
    {
      key: "ravi", phone: "+14155559912", name: "Ravi Pillai", style: STYLE,
      profiling: { role_title: "Procurement Officer", department: "Procurement",
                   seniority: "I'm an individual contributor",
                   responsibilities: "Purchase orders for the warehouse and new supplier set-up",
                   tools: "NAV, Outlook and Excel" },
      facts: <<~FACTS
        - Purchase orders: about 20 POs a week for the warehouse. After sending each one you chase the
          supplier by email or phone to confirm it — about 10 minutes per PO.
        - New supplier set-up: about twice a month you set up a new supplier, which means collecting
          trade licence and bank details by email and typing them into NAV — around two hours each.
        - AI: none.
        - With more time you'd compare supplier prices properly before reordering.
      FACTS
    },
    {
      key: "layla", phone: "+14155559913", name: "Layla Haddad",
      style: "Very terse. Three to ten words per answer. Never volunteer anything extra.",
      profiling: { role_title: "Accounts Payable Clerk", department: "Finance",
                   seniority: "I'm an individual contributor",
                   responsibilities: "Invoice entry and invoice matching",
                   tools: "SAP and Excel" },
      facts: <<~FACTS
        - Invoice entry: about 30 supplier invoices a day into SAP, 3 to 5 minutes each.
        - Matching: about 1 in 5 invoices don't match the PO; you log those in an Excel tracker and
          chase buyers by email. Chasing takes maybe an hour a day in total.
        - AI: none.
        - With more time: do the vendor reconciliations properly.
      FACTS
    },
    {
      key: "omar", phone: "+14155559914", name: "Omar Saleh",
      style: "Plain and factual, two sentences. When asked how something works, you describe how " \
             "long it takes end to end before anything else.",
      profiling: { role_title: "Finance Manager", department: "Finance",
                   seniority: "I'm a manager",
                   responsibilities: "Month-end close and the weekly cash report",
                   team_size: "3 people",
                   tools: "SAP, Excel and Power BI" },
      facts: <<~FACTS
        - Month-end close: it takes about eight working days from month end until the accounts are
          closed, mostly waiting for other teams' figures. Your own part is consolidating exports
          from SAP and two spreadsheets, about two days of your time every month.
        - Weekly cash report: every Monday you rebuild it in Excel from bank statements, about three hours.
        - AI: you tried Copilot in Excel for formulas; not used for anything official.
        - With more time: build a proper rolling cash forecast for the owners.
      FACTS
    },
    {
      key: "noura", phone: "+14155559915", name: "Noura Al Mansoori",
      style: "Clear and organised. Three sentences per answer.",
      profiling: { role_title: "Operations Manager", department: "Operations",
                   seniority: "I'm a manager",
                   responsibilities: "Delivery scheduling, the weekly KPI report and purchase approvals",
                   team_size: "12 people",
                   tools: "ERP, Excel and Outlook" },
      facts: <<~FACTS
        - Delivery scheduling: every afternoon, about an hour, planning the next day's routes in Excel
          from ERP orders.
        - Weekly KPI report: rebuilt by hand in Excel every Monday from three ERP exports, about three
          hours, because nobody trusts the ERP's own report.
        - Purchase approvals: about 15 requests a day by email, 2 to 3 minutes each, but they wait
          whenever you're in meetings.
        - AI: Copilot in Outlook to summarise long email threads.
        - With more time: process improvement projects with the team.
      FACTS
    },
    {
      key: "aisha", phone: "+14155559916", name: "Aisha Rahman", style: STYLE,
      profiling: { role_title: "Sales Coordinator", department: "Sales",
                   seniority: "I'm an individual contributor",
                   responsibilities: "Customer orders and customer statements",
                   tools: "ERP, WhatsApp and Excel" },
      facts: <<~FACTS
        - Customer orders: customers send orders on WhatsApp — about 25 a day. You re-type each into the
          ERP, about 5 minutes each, and sometimes misread handwritten photos.
        - Customer statements: every Friday you email statements of account to about 40 customers,
          which takes around two hours because you export and attach each one by hand.
        - AI: none, you'd be nervous about getting it wrong with customers.
        - With more time: call key customers proactively instead of waiting for orders.
      FACTS
    },
    {
      key: "hamad", phone: "+14155559917", name: "Hamad Al Suwaidi", style: STYLE,
      profiling: { role_title: "HR Officer", department: "HR",
                   seniority: "I'm an individual contributor",
                   responsibilities: "Leave requests, payroll inputs and visa renewals",
                   tools: "Excel, email and the ministry portals" },
      facts: <<~FACTS
        - Payroll inputs: once a month you collect overtime and leave from managers by email and build
          the payroll input sheet in Excel — about a full day of work.
        - Leave requests: about 10 a week by email, 5 minutes each to check balances in Excel and reply.
        - Visa renewals: you track expiry dates in a spreadsheet; renewals wait on the ministry portal,
          sometimes for weeks.
        - AI: none.
        - With more time: put together a proper onboarding pack for new starters.
      FACTS
    }
  ].freeze

  def self.call(only: ENV["ONLY"])
    new(only: only).call
  end

  def initialize(only:)
    keys = only.to_s.split(",").map(&:strip).reject(&:blank?)
    @people = keys.any? ? PEOPLE.select { |p| keys.include?(p[:key]) } : PEOPLE
  end

  def call
    company = ensure_company!
    failed = @people.filter_map do |person|
      DiscoverySimulator.new(slug: company.slug, persona: person, cleanup: false).call
      nil
    rescue RuntimeError => e
      # One person's failed check is worth reporting, not worth losing the others for.
      raise unless e.message.start_with?("Dry run failed")

      "#{person[:key]}: #{e.message}"
    end
    print_findings(company.reload)
    puts "\nInterviews with failed checks:\n  #{failed.join("\n  ")}" if failed.any?
    company
  end

  private

  def ensure_company!
    company = Company.find_or_initialize_by(slug: SLUG)
    company.assign_attributes(COMPANY)
    company.save!
    assign_consultant!(company)
    company
  end

  # The local fixture consultant, so the findings page and report review can be
  # opened as reviewer@reqapp.local.
  def assign_consultant!(company)
    consultant = ConsultantUser.find_by(email: "reviewer@reqapp.local")
    admin = PlatformUser.first
    return unless consultant && admin

    ConsultantAssignment.find_or_create_by!(company: company, consultant_user: consultant) do |a|
      a.assigned_by_platform_user = admin
      a.status = "active"
      a.assigned_at = Time.current
    end
  end

  def print_findings(company)
    # Normally a background job after each interview; built here so the listing
    # does not race it.
    company.conversations.where(status: %w[completed abandoned]).find_each do |conversation|
      Findings::BuildFromConversation.call(conversation: conversation)
    end
    puts "\n=== Findings at #{company.name}"
    company.findings.order(:department, :role_title, :id).each do |f|
      hours = f.annual_hours_min ? "#{f.annual_hours_min}-#{f.annual_hours_max} h/yr" : "(#{f.hours_basis['reason'] || 'no hours'})"
      puts format("  %-12s %-24s %-28s %-24s %-22s %s", f.department, f.role_title, f.area.truncate(28),
                  f.frequency_as_said.to_s.truncate(24), f.duration_as_said.to_s.truncate(22), hours)
    end
  end
end
