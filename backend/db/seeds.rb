# frozen_string_literal: true

puts "Seeding..."

platform = PlatformUser.find_or_create_by!(email: "admin@reqapp.local") do |u|
  u.name = "Platform Admin"
  u.password = "password123"
  u.role = "super_admin"
  u.jti = SecureRandom.uuid
end
puts "Platform user: #{platform.email} / password123"

company = Company.find_or_create_by!(slug: "acme-corp") do |c|
  c.name = "Acme Corp"
  c.display_name = "Acme Corporation"
  c.locale = "en"
  c.portal_onboarding_completed_at = nil
end

Subscription.find_or_create_by!(company: company) do |s|
  s.plan = "trial"
  s.status = "trial"
  s.trial_ends_at = 30.days.from_now
  s.conversation_limit = Subscriptions::PlanLimits.conversation_limit_for("trial")
end

company_admin = CompanyUser.find_or_create_by!(company: company, email: "admin@acme.local") do |u|
  u.name = "Acme Admin"
  u.password = "password123"
  u.role = "company_admin"
  u.status = "active"
  u.jti = SecureRandom.uuid
end
puts "Company admin: #{company_admin.email} / password123 (company: #{company.name})"

ConsentTextVersion.where(active: true).update_all(active: false)

ConsentTextVersion.find_or_create_by!(version: "2026-05-01", locale: "en") do |c|
  c.body = <<~TEXT.squish
    Before we begin: we'll ask about 10 questions about your daily workflows via WhatsApp.
    Your answers help your company find improvement opportunities. Summarized insights are
    shared with authorized leads—not raw chat logs. Reply YES to continue or STOP to opt out.
  TEXT
  c.confirmation_keywords = %w[YES I\ AGREE]
  c.active = true
end

ConsentTextVersion.find_or_create_by!(version: "2026-05-01", locale: "es") do |c|
  c.body = <<~TEXT.squish
    Antes de comenzar: te haremos unas 10 preguntas sobre tus flujos de trabajo por WhatsApp.
    Tus respuestas ayudan a tu empresa a encontrar oportunidades de mejora. Los responsables
    autorizados ven resúmenes, no el chat completo. Responde SI para continuar o STOP para cancelar.
  TEXT
  c.confirmation_keywords = %w[SI YES]
  c.active = true
end

%w[finance sales hr operations support executive default].each do |dept|
  DiscoveryPlaybook.find_or_create_by!(department: dept, version: 1) do |p|
    p.prompt_block = "You are conducting workflow discovery for a #{dept} team member. Ask adaptive, concise questions about their daily processes, tools, pain points, and time sinks. One question at a time."
    p.active = true
    p.activated_at = Time.current
    p.created_by_platform_user = platform
  end
end

[
  { name: "Zapier", vendor: "Zapier", category: "automation", tags: %w[manual_process automation], match_keywords: %w[workflow automate integration] },
  { name: "UiPath", vendor: "UiPath", category: "automation", tags: %w[manual_process], match_keywords: %w[rpa excel manual] },
  { name: "Bill.com", vendor: "Bill.com", category: "saas", tags: %w[manual_process finance], match_keywords: %w[invoice ap accounting] },
  { name: "Make", vendor: "Celonis", category: "integration", tags: %w[tool_dependency data_silo], match_keywords: %w[integrate sync erp] },
  { name: "Notion AI", vendor: "Notion", category: "ai_agent", tags: %w[communication], match_keywords: %w[document knowledge] }
].each do |attrs|
  SolutionCatalogEntry.find_or_create_by!(name: attrs[:name]) do |s|
    s.assign_attributes(attrs.merge(active: true, partnership_tier: "preferred", description: "Curated solution for workflow discovery recommendations."))
  end
end

company.update!(portal_onboarding_completed_at: Time.current) if company.portal_onboarding_completed_at.blank?
company.update!(settings: company.settings.merge("allow_early_report" => true, "skip_platform_review" => false))

reviewer = ReviewerUser.find_or_create_by!(email: "reviewer@reqapp.local") do |u|
  u.name = "Expert Reviewer"
  u.password = "password123"
  u.status = "active"
  u.jti = SecureRandom.uuid
end
puts "Reviewer: #{reviewer.email} / password123"

ReviewerAssignment.find_or_create_by!(company: company, reviewer_user: reviewer, status: "active") do |a|
  a.assigned_by_platform_user = platform
  a.assigned_at = Time.current
end

puts "Done."
