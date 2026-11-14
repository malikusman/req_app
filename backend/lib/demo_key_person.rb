# frozen_string_literal: true

# Runs the key user's conversation with leadership end to end on the demo
# company, through the same API the screen calls (Doc 08):
#
#   consent → the opening → scripted answers from the owner of a trading
#   company → read-back → the scope card settles the "Not sure" counts and adds
#   a manager they mention → a document is uploaded → the context is built →
#   the engagement hands over to Stage 1 pricing.
#
# Picks up where `rails demo:onboarding` leaves off (run it first, or pass
# FRESH=1 to run it now). Without REAL=1 the model is replaced by scripted
# replies, so the run needs no API key; with REAL=1 the configured model writes
# the questions and reads the answers.
#
#   rails demo:key_person                 # scripted replies
#   rails demo:key_person REAL=1 FRESH=1  # the real model, from a fresh onboarding
class DemoKeyPerson
  # What the owner says to each area when it is asked about. The demo reads the
  # area the last question targeted from the database — the participant's screen
  # never shows it — so the answers fit the questions whichever order the
  # planner (or, with REAL=1, the model) takes.
  ANSWERS = {
    "STRATEGIC_OBJECTIVES" => "In two years I want us selling properly into Saudi and East Africa, not just the UAE. " \
                              "We're too dependent on a handful of big retail customers.",
    "GROWTH_PRIORITIES" => "Growth is limited by handling what we have. We can't keep up with orders as it is.",
    "CONCERNS" => "Honestly the thing I chase most is quotations. Half of them sit waiting for my approval and " \
                  "customers go elsewhere.",
    "BOTTLENECKS" => "Orders pile up because everything comes in on WhatsApp and gets typed into Zoho by hand.",
    "STAKEHOLDER_EXPERIENCE" => "Our best customers complain that we're slow to confirm stock and delivery dates.",
    "PEOPLE_WORKLOAD" => "Our sales coordinator holds everything in her head. Omar in procurement knows the day-to-day " \
                         "better than anyone too.",
    "SYSTEMS" => "We work around Zoho constantly; half the team keeps their own spreadsheets next to it.",
    "REPORTING" => "I'd love to see stock and margin by customer every morning. Today I get it once a month in the " \
                   "monthly management pack.",
    "DECISIONS_APPROVALS" => "Every discount and most quotes come to me. I'd rather only see the big ones.",
    "DATA_DOCUMENTS" => "Our finance team prepares the weekly sales pack by hand from three spreadsheets.",
    "PLANNED_INITIATIVES" => "We're moving to a new ERP next year, probably in March, so I don't want anything that " \
                             "fights that.",
    "CONSTRAINTS" => "Don't disturb the warehouse during Ramadan and the year-end stock count; those are our busiest weeks.",
    "SUCCESS_DEFINITION" => "Success would be quotes going out the same day and me not being the bottleneck any more.",
    "PRIORITY_AREAS" => "Look at sales and the quotation process first. That's where the money leaks.",
    "AMBITION" => "We'd like to win customers we can't serve today, like online retailers who need fast quotes.",
    "RELEASED_TIME" => "If the sales team had a few hours back I'd want them out visiting customers and opening new accounts."
  }.freeze
  # Turns that aren't about one area.
  BY_MODE = {
    "OPENING" => "Yes, let's go.",
    "PRIORITY_READ_BACK" => "The quotations, without a doubt.",
    "SCOPE_AND_PARTICIPANTS" => "Sales and procurement mostly. Omar in procurement knows how the day runs.",
    "DOCUMENT_REQUEST" => "Sure, I'll share the weekly sales pack.",
    "ANYTHING_ELSE" => "No, I think we've covered it."
  }.freeze
  # Asked once, part-way through, to show a question being handled.
  ASIDE = "What would all this cost us, roughly?"
  FILLER = "Nothing more to add on that — it's covered."

  def self.call(company_id: ENV.fetch("COMPANY_ID", 3), real: ENV["REAL"].present?, fresh: ENV["FRESH"].present?)
    new(company_id: company_id, real: real, fresh: fresh).call
  end

  def initialize(company_id:, real:, fresh:)
    @company = Company.find(company_id)
    @real = real
    @fresh = fresh
    @http = ActionDispatch::Integration::Session.new(Rails.application)
    @http.host! "localhost"
  end

  def call
    ENV["KEY_PERSON_SCRIPTED_REPLIES"] = "1" unless @real
    DemoOnboarding.call(company_id: @company.id, real: false, website: nil) if @fresh
    engagement = @company.reload.current_engagement
    raise "Run `rails demo:onboarding` first: the engagement is #{engagement&.status || 'missing'}" unless engagement&.status == "KEY_PERSON_DISCOVERY"

    KeyPerson::Kickoff.call(engagement)
    token = sign_in
    say "Company #{@company.id}: #{@company.display_name || @company.name} — #{@real ? 'the real model' : 'scripted replies'}"

    data = request(:post, "/api/v1/company/leadership/consent", nil, token)
    show_new_turns(data)
    own = engagement.participants.find_by!(source: "KEY_USER")
    used = Set.new
    asked_aside = false
    60.times do
      session = data["session"]
      break if session["finished"]

      data = settle_scope(token, data) if session["state"] == "SCOPE_AND_PARTICIPANTS"
      last = own.conversation_sessions.last.turns.from_assistant.last
      text = if !asked_aside && used.size == 6 && last.mode == "QUESTION"
               asked_aside = true
               ASIDE
             elsif (area = last.targeted_slot) && ANSWERS[area] && !used.include?(area)
               used << area
               ANSWERS[area]
             else
               BY_MODE[last.mode] || FILLER
             end
      data = request(:post, "/api/v1/company/leadership/messages", { text: text, client_message_id: SecureRandom.uuid }, token)
      show_new_turns(data)
    end
    data = settle_scope(token, data) unless data.dig("scope", "counts_known")
    upload_document(token, data)

    session = engagement.participants.find_by!(source: "KEY_USER").conversation_sessions.last
    KeyPerson::ContextBuilder.call(session)
    report(engagement.reload, session.reload)
  ensure
    ENV.delete("KEY_PERSON_SCRIPTED_REPLIES") unless @real
  end

  private

  def sign_in
    data = request(:post, "/api/v1/auth/company/login",
                   { email: DemoOnboarding::KEY_USER_EMAIL, password: DemoOnboarding::KEY_USER_PASSWORD })
    data["token"] || raise("Couldn't sign in as #{DemoOnboarding::KEY_USER_EMAIL}")
  end

  # The scope card: every "Not sure" becomes a number, and a manager mentioned
  # in passing joins the plan.
  def settle_scope(token, data)
    scope = data["scope"] || {}
    departments = Array(scope["departments"]).map do |d|
      { name: d["name"], count: d["count"] == "UNKNOWN" ? 2 : d["count"] }
    end
    data = request(:patch, "/api/v1/company/leadership/scope", { departments: departments }, token)
    say "  [scope card] counts settled: #{departments.map { |d| "#{d[:name]} #{d[:count]}" }.join(', ')}"
    Array(scope["people_mentioned"]).first(1).each do |person|
      data = request(:post, "/api/v1/company/leadership/people",
                     { index: person["index"], participant: { participant_type: "EMPLOYEE", name: person["name"],
                                                              department: person["department"] } }, token)
      say "  [scope card] added #{person['name']} (#{person['department']}) to the plan"
    end
    data
  end

  def upload_document(token, data)
    request_row = Array(data.dig("session", "document_requests")).first
    return unless request_row

    file = Rack::Test::UploadedFile.new(StringIO.new("Weekly sales pack — demo"), "text/plain",
                                        original_filename: "weekly-sales-pack.txt")
    @http.post("/api/v1/company/leadership/documents", params: { file: file, document_request_id: request_row["id"] },
                                                       headers: { "Authorization" => "Bearer #{token}" })
    say "  [upload] #{request_row['requested_item']} → #{@http.response.status}"
  rescue StandardError => e
    say "  [upload] skipped: #{e.message}"
  end

  def show_new_turns(data)
    @shown ||= 0
    turns = Array(data.dig("session", "turns"))
    turns.drop(@shown).each { |t| say "#{t['from'] == 'assistant' ? 'Mjadi' : 'Owner'}: #{t['text']}" }
    @shown = turns.size
  end

  def report(engagement, session)
    context = session.management_discovery_context
    say ""
    say "Session #{session.state}, closed: #{session.close_reason}, #{session.turns.from_participant.count} answers"
    say "Coverage:"
    KeyPerson::Coverage::AREAS.each do |area|
      say format("  %-24s %s", area, session.state_snapshot.dig("coverage", area, "status") || "OPEN")
    end
    if context
      say "Context v#{context.version}: #{context.status}"
      context.strategic_findings.each { |f| say "  Finding (#{f.category}, #{f.evidence.join(' ')}): #{f.statement.truncate(110)}" }
      context.planned_initiatives.each { |i| say "  Planned: #{i.initiative_type} — #{i.description.truncate(90)}" }
      context.neutral_employee_context.each { |n| say "  May reach staff (#{n['department']}): #{n['context']}" }
    end
    say "Planned: #{engagement.planned_departments.map { |d| "#{d['name']} #{d['count']}" }.join(', ')} = " \
        "#{engagement.planned_participant_count || 'not yet known'}"
    say "Engagement: #{engagement.status_history.last&.values_at('from', 'to')&.join(' → ')} (now #{engagement.status})"
    say "Model calls: #{AiRun.where(subject: session).or(AiRun.where(subject: session.turns)).group(:stage, :status).count}"
    manager = engagement.participants.planned.key_persons.first
    say "A manager's link: #{KeyPerson::Invite.new(manager).link!}" if manager
  end

  def request(verb, path, body = nil, token = nil)
    headers = { "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    @http.public_send(verb, path, params: body&.to_json, headers: headers)
    unless @http.response.successful?
      raise "#{verb.upcase} #{path} → #{@http.response.status}: #{@http.response.body.truncate(300)}"
    end

    @http.response.body.present? ? JSON.parse(@http.response.body) : {}
  end

  def say(line)
    puts line
  end
end
