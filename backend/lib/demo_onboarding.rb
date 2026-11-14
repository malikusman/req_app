# frozen_string_literal: true

# Runs company onboarding end to end on a demo company (Gulf Trading Co.,
# company 3, by default), through the same API the screens call:
#
#   Mjadi sets up the engagement → the website is read for proposals → the key
#   user accepts the invitation → confirms and corrects proposals → answers the
#   remaining facts ("Not sure" where they don't know) → plans who takes part →
#   acknowledges → submits, handing over to the leadership conversation.
#
# The company's existing employees, interviews, findings and reports are not
# touched. Its current engagement is closed (with a reason) and a new one opened,
# so the run can be repeated.
#
#   rails demo:onboarding                      # company 3, saved fixture website
#   rails demo:onboarding COMPANY_ID=3 REAL=1  # read a real website (WEBSITE=…)
#
# With a model configured the website proposals are real P01 output; without
# one the pre-fill falls back to the plain form, and the run carries on.
class DemoOnboarding
  KEY_USER_EMAIL = "keyuser@gulf-trading.demo"
  KEY_USER_PASSWORD = "demo-onboarding-1"
  FIXTURE_SITE = "https://example-trading.ae/"
  FIXTURES = Rails.root.join("spec/fixtures/websites")

  def self.call(company_id: ENV.fetch("COMPANY_ID", 3), real: ENV["REAL"].present?, website: ENV["WEBSITE"])
    new(company_id: company_id, real: real, website: website).call
  end

  def initialize(company_id:, real:, website:)
    @company = Company.find(company_id)
    @real = real
    @website = website.presence || (real ? @company.website_url.presence : nil) || FIXTURE_SITE
    @admin = PlatformUser.order(:id).first || raise("No platform user — run db:seed first")
    @http = ActionDispatch::Integration::Session.new(Rails.application)
    @http.host! "localhost"
  end

  def call
    say "Company #{@company.id}: #{@company.display_name || @company.name}"
    close_current_engagement!
    engagement = set_up_engagement!
    read_website!(engagement)
    token = accept_invitation!
    answer_proposals!(token)
    fill_the_form!(token)
    plan_people!(token)
    submit!(token)
    report(engagement.reload)
  end

  private

  def close_current_engagement!
    current = @company.current_engagement
    return unless current

    Engagements::Transition.call(engagement: current, to: "CLOSED", actor: @admin, force: true,
                                 reason: "Demo: onboarding run again")
    say "Closed engagement ##{current.id} (#{current.status_history.last['from']})"
  end

  # Approval path of Engagements::Create: the company already exists; the key user
  # is created (or reset) here as a pending, invited account.
  def set_up_engagement!
    key_user = CompanyUser.find_or_initialize_by(email: KEY_USER_EMAIL)
    key_user.assign_attributes(company: @company, name: "Huda Saleh", role: "company_admin", status: "pending",
                               phone: "+971500001234", password: SecureRandom.base58(24))
    key_user.save!
    lead = ConsultantUser.find_by(email: "reviewer@reqapp.local") || ConsultantUser.where(status: "active").first
    # The website is set after set-up, so set-up doesn't queue its own background
    # read alongside the one this run makes.
    @company.update_columns(website_url: nil)
    engagement = Engagements::Create.call(
      platform_user: @admin, company: @company, key_user: key_user,
      params: { scope_type: "COMPANY", lead_consultant_id: lead&.id, languages: %w[en ar],
                proposal_reference: "P-DEMO-#{Time.current.strftime('%Y%m%d%H%M')}",
                key_user: { role_title: "General Manager" } }
    )
    say "Set up engagement ##{engagement.id} — #{engagement.status}, invitation sent to #{KEY_USER_EMAIL}"
    engagement
  end

  def read_website!(engagement)
    @company.update_columns(website_url: @website)
    pages = @real ? nil : fixture_pages
    Companies::WebsitePrefill.call(engagement: engagement, pages: pages)
    engagement.reload
    say "Read #{@real ? @website : 'the saved fixture website'}: #{engagement.prefill_status}" \
        "#{engagement.prefill_error ? " (#{engagement.prefill_error})" : ''}, " \
        "#{engagement.prefill_candidates.count} proposals"
  end

  def fixture_pages
    %w[trading_home.html trading_about.html trading_contact.html].each_with_index.map do |file, i|
      html = FIXTURES.join(file).read
      url = [FIXTURE_SITE, "#{FIXTURE_SITE}about-us", "#{FIXTURE_SITE}contact"][i]
      Companies::WebsiteFetcher.page_from_html(url, html)
    end
  end

  def accept_invitation!
    user = CompanyUser.find_by!(email: KEY_USER_EMAIL)
    token = Auth::PasswordResetToken.generate(user, ttl: Auth::PasswordResetToken::INVITATION_TTL)
    Auth::SetPassword.call(token: token, password: KEY_USER_PASSWORD, password_confirmation: KEY_USER_PASSWORD)
    body = request(:post, "/api/v1/auth/company/login", { email: KEY_USER_EMAIL, password: KEY_USER_PASSWORD })
    say "Key user set a password and signed in — engagement now #{@company.current_engagement.status}"
    body["token"]
  end

  # Confirm industry and locations, edit the products, leave the rest alone.
  def answer_proposals!(token)
    proposals = request(:get, "/api/v1/company/onboarding", nil, token).dig("prefill", "candidates") || []
    actions = { "industry" => "confirm", "locations" => "confirm", "products_services" => "correct" }
    proposals.each do |p|
      action = actions[p["target_field"]] or next
      out = request(:post, "/api/v1/company/onboarding/prefill_candidates/#{p['id']}/#{action}", nil, token)
      say "  #{action.ljust(7)} #{p['target_field']}: #{p['display_text'].to_s.truncate(70)}"
      next unless action == "correct"

      edited = out["answers"].transform_values { |v| "#{v} Also sewing machines and spare parts." }
      request(:patch, "/api/v1/company/onboarding/questionnaire/answers", { answers: edited }, token)
    end
  end

  def fill_the_form!(token)
    request(:patch, "/api/v1/company/onboarding/questionnaire/answers", { answers: {
      o02_headcount: "51–200", o03_hq_country: "United Arab Emirates", o04_business_model: %w[B2B Wholesale],
      o06_departments: %w[Procurement Sales Finance Operations HR], o07_channels: %w[WhatsApp Phone Email],
      o08_systems: ["Accounting software", "Spreadsheets", "Other"],
      o08_systems_other: "Zoho Books", o09_data_storage: "Not sure", o10_ai_tools: %w[ChatGPT],
      o11_constraints: "Not sure", a4_language: "English"
    } }, token)
    say "Answered the facts — data storage and constraints as Not sure"
  end

  def plan_people!(token)
    request(:patch, "/api/v1/company/onboarding/questionnaire/answers", { answers: {
      p1_departments: %w[Procurement Sales Finance],
      p2_department_counts: { "Procurement" => "2", "Sales" => "2", "Finance" => "1" }
    } }, token)
    request(:post, "/api/v1/company/onboarding/participants",
            { participant: { participant_type: "EMPLOYEE", name: "Shiv Kumar", role_title: "Procurement Officer",
                             department: "Procurement" } }, token)
    request(:post, "/api/v1/company/onboarding/participants",
            { participant: { participant_type: "KEY_PERSON", name: "Rania Haddad", role_title: "Head of Sales",
                             scope: "Sales, UAE and GCC" } }, token)
    say "Planned Procurement 2, Sales 2, Finance 1; named one participant and one manager to speak with"
  end

  def submit!(token)
    request(:post, "/api/v1/company/onboarding/submit", { answers: {}, confidentiality_acknowledged: true }, token)
    say "Acknowledged and submitted"
  end

  def report(engagement)
    profile = @company.reload.company_profile
    say ""
    say "Engagement ##{engagement.id}: #{engagement.status}; acknowledgement version #{engagement.confidentiality_text_version}"
    say "Planned: #{engagement.planned_departments.map { |d| "#{d['name']} #{d['count']}" }.join(', ')} " \
        "= #{engagement.planned_participant_count || 'not yet known'}"
    say "People: #{engagement.participants.map { |p| "#{p.name} (#{p.participant_type.downcase})" }.join(', ')}"
    say "Proposals: #{engagement.prefill_candidates.group(:status).count}"
    say ""
    say "Field                  Value                                              Source"
    @company.profile_provenance.sort.each do |field, entry|
      value = entry["unknown"] ? "Not sure" : Array(profile[field]).join(", ")
      say format("%-22s %-50s %s", field, value.truncate(50), entry["source"])
    end
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
