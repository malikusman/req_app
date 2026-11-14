# frozen_string_literal: true

# Runs Stage 1 pricing end to end on the demo company, through the same API the
# screens call (Doc 17 §1–§12):
#
#   the platform proposes the quote → P24 explains it → an administrator
#   corrects the inputs (four deep dives; two locations, since the profile's
#   free text reads as four) and approves → the key user reads the proposal
#   and accepts → Stage 1 starts → the team is invited up to what the price
#   covers, and one more only once the client confirms the extra charge.
#
# Picks up where `rails demo:key_person` leaves off (company 3, Gulf Trading
# Co., in STAGE_1_PRICING). FRESH=1 runs onboarding and the leadership
# conversation first. Without REAL=1, P24 is replaced by scripted replies, so
# the run needs no API key.
#
#   rails demo:pricing                 # scripted P24
#   rails demo:pricing REAL=1 FRESH=1  # the real model, from a fresh onboarding
class DemoPricing
  ADMIN_EMAIL = "admin@reqapp.local"
  ADMIN_PASSWORD = "password123"
  # Words that would mean internal pricing data reached the client (Doc 17 §15).
  INTERNAL = /margin|cost|hours|rate_card|override|floor|estimate|admin_explanation/i

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
    ENV["PRICING_SCRIPTED_REPLIES"] = "1" unless @real
    DemoKeyPerson.call(company_id: @company.id, real: @real, fresh: true) if @fresh
    engagement = @company.reload.current_engagement
    unless engagement&.status == "STAGE_1_PRICING"
      raise "Run `rails demo:key_person` first (or pass FRESH=1): the engagement is #{engagement&.status || 'missing'}"
    end

    Pricing::Defaults.ensure!
    say "Company #{@company.id}: #{@company.display_name || @company.name}, engagement ##{engagement.id} — " \
        "#{@real ? 'P24 on the real model' : 'scripted P24'}"

    admin = sign_in("platform", ADMIN_EMAIL, ADMIN_PASSWORD)
    quote = propose(engagement, admin)
    quote = correct_inputs(quote, admin)
    issue(quote, admin)

    client = sign_in("company", DemoOnboarding::KEY_USER_EMAIL, DemoOnboarding::KEY_USER_PASSWORD)
    accept(client)
    invite_team(client, engagement.reload)
    report(engagement.reload)
  ensure
    ENV.delete("PRICING_SCRIPTED_REPLIES") unless @real
  end

  private

  # The quote the platform proposed on hand-over, or worked out now if the
  # engagement reached pricing before quotes existed.
  def propose(engagement, admin)
    quote = engagement.open_stage1_quote
    quote ||= Quote.find(request(:post, "/api/v1/platform/engagements/#{engagement.id}/stage1_quote", nil, admin).dig("quote", "id"))
    explain(quote)
    show_admin_view(quote, "Proposed")
    quote
  end

  def correct_inputs(quote, admin)
    data = request(:post, "/api/v1/platform/stage1_quotes/#{quote.id}/change_inputs",
                   { deep_dives: 4, locations: 2 }, admin)
    quote = Quote.find(data.dig("quote", "id"))
    say ""
    say "[admin] Inputs corrected — 4 deep dives, 2 locations — as v#{quote.version}; v#{quote.version - 1} superseded"
    explain(quote)
    show_admin_view(quote, "Corrected")
    quote
  end

  def issue(quote, admin)
    body = quote.below_floor ? { floor_override: { reason: "RELATIONSHIP", free_text: "Demo: pilot client" } } : {}
    data = request(:post, "/api/v1/platform/stage1_quotes/#{quote.id}/approve", body, admin)
    say ""
    say "[admin] Approved and issued v#{data.dig('quote', 'version')}, valid until #{data.dig('quote', 'valid_until')}"
  end

  def accept(client)
    data = request(:get, "/api/v1/company/stage1_quote", nil, client)
    view = data["quote"]
    say ""
    say "[client] #{view['company_name']} sees #{Pricing::Money.format(view['total'], view['currency'])} including VAT:"
    view["line_items"].each { |l| say format("  %-38s %s", l["label"], Pricing::Money.format(l["amount"], view["currency"])) }
    say "  Included: #{view.dig('scope', 'what_is_included').first(2).join('; ')}…"
    say "  Extra people: #{view.dig('scope', 'additional_participants')}"
    say "  Internal words in what the client received: #{@http.response.body.scan(INTERNAL).uniq.presence || 'none'}"
    request(:post, "/api/v1/company/stage1_quotes/#{view['id']}/accept", { acknowledged: true }, client)
    say "[client] Accepted"
  end

  # Up to what the price covers, then one more: refused until the client
  # confirms the extra charge, then flagged (Doc 17 §12).
  def invite_team(client, engagement)
    staff = Engagements::StaffInvitations.new(@company)
    room = [staff.included - staff.invited, 0].max
    say ""
    say "[team] The price covers #{staff.included}; #{staff.invited} invited so far. Inviting #{room}, then one more."
    room.times { |i| invite(client, "Team member #{i + 1}") }
    @http.post("/api/v1/company/employees", params: invitation("Extra person").to_json, headers: headers(client))
    refusal = JSON.parse(@http.response.body)
    say "[team] One more → #{@http.response.status}: #{refusal['error']}"
    invite(client, "Extra person", confirm_additional: true)
    say "[team] Confirmed → invited and flagged added_after_pricing " \
        "(#{engagement.participants.where(added_after_pricing: true).employees.count} flagged)"
  end

  def invite(client, name, confirm_additional: false)
    request(:post, "/api/v1/company/employees", invitation(name).merge(confirm_additional: confirm_additional), client)
  end

  def invitation(name)
    { phone_e164: "+97150#{rand(1_000_000..9_999_999)}", display_name: name, send_whatsapp: false }
  end

  def explain(quote)
    ExplainStage1QuoteJob.perform_now(quote.id)
    quote.reload
  end

  def show_admin_view(quote, heading)
    e = quote.estimate
    say ""
    say "#{heading}: v#{quote.version} — #{Pricing::Money.format(quote.total, quote.currency)} including VAT " \
        "(#{quote.participants_included} people, #{quote.deep_dives_included} deep dives)"
    quote.line_items.each { |l| say format("  %-38s %s", l["label"], Pricing::Money.format(l["amount"], quote.currency)) }
    say "  Hours #{e['total_hours']} · fully loaded cost #{Pricing::Money.format(e.dig('cost', 'total'), quote.currency)} · " \
        "margin #{quote.margin_percent}% (floor #{e['floor_percent']}%) · confidence #{e['confidence']}"
    say "  Risks: #{e['risk_signals'].map { |s| s['text'] }.join('; ')}"
    say "  P24 (#{quote.explanation_source}): #{quote.admin_explanation['headline'] || 'no explanation — template used'}"
  end

  def report(engagement)
    quote = engagement.accepted_stage1_quote
    extras = Pricing::AdditionalParticipants.for(engagement)
    say ""
    say "Engagement: #{engagement.status_history.last(2).map { |h| "#{h['from']} → #{h['to']}" }.join(', ')} (now #{engagement.status})"
    say "Accepted v#{quote.version} by #{quote.accepted_by.name}; events: #{quote.events.map(&:event).join(', ')}"
    say "Versions: #{engagement.quotes.stage1.order(:version).map { |q| "v#{q.version} #{q.status}" }.join(', ')}"
    say "Added after pricing: #{extras[:count]} × #{Pricing::Money.format(extras[:rate], extras[:currency])} = " \
        "#{Pricing::Money.format(extras[:amount], extras[:currency])}"
    say "P24 runs: #{AiRun.where(stage: 'P24', engagement_id: engagement.id).group(:status).count}"
    say "Emails waiting in Mailpit (sent by Sidekiq): http://localhost:8025"
  end

  def sign_in(portal, email, password)
    data = request(:post, "/api/v1/auth/#{portal}/login", { email: email, password: password })
    data["token"] || raise("Couldn't sign in as #{email}")
  end

  def headers(token) = { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }

  def request(verb, path, body = nil, token = nil)
    hdrs = { "Content-Type" => "application/json" }
    hdrs["Authorization"] = "Bearer #{token}" if token
    @http.public_send(verb, path, params: body&.to_json, headers: hdrs)
    unless @http.response.successful?
      raise "#{verb.upcase} #{path} → #{@http.response.status}: #{@http.response.body.truncate(300)}"
    end

    @http.response.body.present? ? JSON.parse(@http.response.body) : {}
  end

  def say(line)
    puts line
  end
end
