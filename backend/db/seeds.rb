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

ConsentTextVersion.find_or_create_by!(version: "2026-06-20", locale: "en") do |c|
  c.body = <<~TEXT.squish
    Before we begin: we'll ask about 10 questions about your daily workflows via WhatsApp.
    You can reply with text, voice notes, screenshots, or PDFs if that's easier.
    Optional media may be transcribed or analyzed by AI to understand your work; only summarized
    insights are shared with authorized leads—not raw chat logs or original files.
    Reply YES to continue or STOP to opt out.
  TEXT
  c.confirmation_keywords = %w[YES I\ AGREE]
  c.active = true
end

ConsentTextVersion.find_or_create_by!(version: "2026-06-20", locale: "es") do |c|
  c.body = <<~TEXT.squish
    Antes de comenzar: te haremos unas 10 preguntas sobre tus flujos de trabajo por WhatsApp.
    Puedes responder con texto, notas de voz, capturas o PDFs si te resulta más fácil.
    Los medios opcionales pueden transcribirse o analizarse con IA; los responsables autorizados
    ven resúmenes, no el chat completo ni los archivos originales. Responde SI para continuar o STOP para cancelar.
  TEXT
  c.confirmation_keywords = %w[SI YES]
  c.active = true
end

ConsentTextVersion.find_or_create_by!(version: "2026-05-01", locale: "en") do |c|
  c.body = <<~TEXT.squish
    Before we begin: we'll ask about 10 questions about your daily workflows via WhatsApp.
    Your answers help your company find improvement opportunities. Summarized insights are
    shared with authorized leads—not raw chat logs. Reply YES to continue or STOP to opt out.
  TEXT
  c.confirmation_keywords = %w[YES I\ AGREE]
  c.active = false
end

ConsentTextVersion.find_or_create_by!(version: "2026-05-01", locale: "es") do |c|
  c.body = <<~TEXT.squish
    Antes de comenzar: te haremos unas 10 preguntas sobre tus flujos de trabajo por WhatsApp.
    Tus respuestas ayudan a tu empresa a encontrar oportunidades de mejora. Los responsables
    autorizados ven resúmenes, no el chat completo. Responde SI para continuar o STOP para cancelar.
  TEXT
  c.confirmation_keywords = %w[SI YES]
  c.active = false
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
company.update!(settings: company.settings.merge(
  "allow_early_report" => true,
  "skip_platform_review" => false,
  "discovery_profiling_enabled" => true,
  "discovery_multi_agent_enabled" => true,
  "discovery_memory_retrieval_enabled" => true,
  "discovery_media_indexing_enabled" => true,
  "discovery_question_target" => 12
))

reviewer = ReviewerUser.find_or_create_by!(email: "reviewer@reqapp.local") do |u|
  u.name = "Expert Reviewer"
  u.password = "password123"
  u.status = "active"
  u.jti = SecureRandom.uuid
end
puts "Reviewer: #{reviewer.email} / password123"

ReviewerUser.find_or_create_by!(email: "reviewer2@reqapp.local") do |u|
  u.name = "Finance Specialist"
  u.password = "password123"
  u.status = "active"
  u.jti = SecureRandom.uuid
end
puts "Reviewer: reviewer2@reqapp.local / password123"

ReviewerAssignment.find_or_create_by!(company: company, reviewer_user: reviewer, status: "active") do |a|
  a.assigned_by_platform_user = platform
  a.assigned_at = Time.current
end

beta = Company.find_or_create_by!(slug: "beta-industries") do |c|
  c.name = "Beta Industries"
  c.display_name = "Beta Industries"
  c.locale = "en"
  c.portal_onboarding_completed_at = Time.current
end

Subscription.find_or_create_by!(company: beta) do |s|
  s.plan = "trial"
  s.status = "trial"
  s.trial_ends_at = 4.days.from_now
  s.conversation_limit = Subscriptions::PlanLimits.conversation_limit_for("trial")
end

CompanyUser.find_or_create_by!(company: beta, email: "admin@beta.local") do |u|
  u.name = "Beta Admin"
  u.password = "password123"
  u.role = "company_admin"
  u.status = "active"
  u.jti = SecureRandom.uuid
end

beta.update!(settings: beta.settings.merge(
  "allow_early_report" => true,
  "skip_platform_review" => false,
  "discovery_profiling_enabled" => true,
  "discovery_multi_agent_enabled" => true,
  "discovery_memory_retrieval_enabled" => true,
  "discovery_media_indexing_enabled" => true,
  "discovery_question_target" => 12
))

ReviewerAssignment.find_or_create_by!(company: beta, reviewer_user: reviewer, status: "active") do |a|
  a.assigned_by_platform_user = platform
  a.assigned_at = Time.current
end

load Rails.root.join("lib/demo_seeder.rb") unless defined?(DemoSeeder)
DemoSeeder.call(slug: company.slug)
BetaDemoSeeder.call(slug: beta.slug)

DemoScript.print_walkthrough

puts "Done."
