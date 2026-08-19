# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_08_19_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "vector"

  create_table "agentic_ideas", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "title", null: false
    t.text "summary"
    t.text "system_fit"
    t.text "value_time"
    t.text "value_efficiency"
    t.text "value_cost"
    t.string "approx_timeline"
    t.string "estimated_cost"
    t.float "confidence", default: 0.5, null: false
    t.string "status", default: "draft", null: false
    t.string "source", default: "generated", null: false
    t.jsonb "related_signal_ids", default: [], null: false
    t.jsonb "related_pattern_ids", default: [], null: false
    t.jsonb "related_stack_ids", default: [], null: false
    t.bigint "solution_catalog_entry_id"
    t.string "created_by_type"
    t.bigint "created_by_id"
    t.string "updated_by_type"
    t.bigint "updated_by_id"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "status"], name: "index_agentic_ideas_on_company_id_and_status"
    t.index ["company_id", "title"], name: "index_agentic_ideas_on_company_id_and_title"
    t.index ["company_id"], name: "index_agentic_ideas_on_company_id"
    t.index ["created_by_type", "created_by_id"], name: "index_agentic_ideas_on_created_by"
    t.index ["solution_catalog_entry_id"], name: "index_agentic_ideas_on_solution_catalog_entry_id"
  end

  create_table "catalog_candidates", force: :cascade do |t|
    t.bigint "catalog_source_record_id"
    t.string "name", null: false
    t.string "vendor"
    t.string "entity_type", default: "tool", null: false
    t.text "description"
    t.string "website_url"
    t.float "confidence", default: 0.0, null: false
    t.string "review_status", default: "pending", null: false
    t.bigint "suggested_catalog_entry_id"
    t.bigint "reviewed_by_platform_user_id"
    t.datetime "reviewed_at"
    t.text "review_note"
    t.jsonb "provenance", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "analysis_status", default: "pending", null: false
    t.datetime "analyzed_at"
    t.datetime "published_at"
    t.jsonb "industries", default: [], null: false
    t.jsonb "topics", default: [], null: false
    t.text "summary"
    t.index ["analysis_status"], name: "index_catalog_candidates_on_analysis_status"
    t.index ["catalog_source_record_id"], name: "index_catalog_candidates_on_catalog_source_record_id"
    t.index ["entity_type"], name: "index_catalog_candidates_on_entity_type"
    t.index ["published_at"], name: "index_catalog_candidates_on_published_at"
    t.index ["review_status"], name: "index_catalog_candidates_on_review_status"
  end

  create_table "catalog_endorsements", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "report_id"
    t.bigint "reviewer_user_id", null: false
    t.bigint "solution_catalog_entry_id"
    t.string "disposition", null: false
    t.text "rationale"
    t.string "source_url"
    t.boolean "publishable", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_catalog_endorsements_on_company_id"
    t.index ["report_id"], name: "index_catalog_endorsements_on_report_id"
    t.index ["reviewer_user_id"], name: "index_catalog_endorsements_on_reviewer_user_id"
    t.index ["solution_catalog_entry_id"], name: "index_catalog_endorsements_on_solution_catalog_entry_id"
  end

  create_table "catalog_entry_aliases", force: :cascade do |t|
    t.bigint "solution_catalog_entry_id", null: false
    t.string "alias_text", null: false
    t.string "normalized_alias", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_alias"], name: "index_catalog_entry_aliases_on_normalized_alias"
    t.index ["solution_catalog_entry_id"], name: "index_catalog_entry_aliases_on_solution_catalog_entry_id"
  end

  create_table "catalog_pricing_snapshots", force: :cascade do |t|
    t.bigint "solution_catalog_entry_id", null: false
    t.string "pricing_model"
    t.string "currency"
    t.string "unit"
    t.decimal "amount", precision: 12, scale: 2
    t.datetime "effective_at"
    t.string "source_url"
    t.text "raw_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["solution_catalog_entry_id"], name: "index_catalog_pricing_snapshots_on_solution_catalog_entry_id"
  end

  create_table "catalog_source_records", force: :cascade do |t|
    t.bigint "catalog_source_id", null: false
    t.bigint "catalog_sync_run_id"
    t.string "external_id", null: false
    t.string "fingerprint", null: false
    t.string "title"
    t.string "url"
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "fetched_at", null: false
    t.string "parse_status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_source_id", "external_id"], name: "idx_catalog_source_records_unique_external", unique: true
    t.index ["catalog_source_id"], name: "index_catalog_source_records_on_catalog_source_id"
    t.index ["catalog_sync_run_id"], name: "index_catalog_source_records_on_catalog_sync_run_id"
  end

  create_table "catalog_sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "source_type", null: false
    t.string "endpoint_url"
    t.string "sync_cron"
    t.datetime "last_sync_at"
    t.string "last_sync_status"
    t.integer "trust_score", default: 50, null: false
    t.boolean "active", default: true, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "catalog_sync_runs", force: :cascade do |t|
    t.bigint "catalog_source_id", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.string "status", default: "running", null: false
    t.integer "records_fetched", default: 0, null: false
    t.integer "candidates_created", default: 0, null: false
    t.integer "embedding_calls", default: 0, null: false
    t.integer "llm_tokens", default: 0, null: false
    t.jsonb "error_details", default: [], null: false
    t.jsonb "budget", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_source_id"], name: "index_catalog_sync_runs_on_catalog_source_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "display_name"
    t.string "logo_storage_key"
    t.string "locale", default: "en", null: false
    t.datetime "portal_onboarding_completed_at"
    t.datetime "pin_rotated_at"
    t.float "report_readiness_score", default: 0.0, null: false
    t.jsonb "settings", default: {}, null: false
    t.jsonb "report_readiness_breakdown", default: {}, null: false
    t.jsonb "intelligence_snapshot", default: {}, null: false
    t.jsonb "security_snapshot", default: {}, null: false
    t.integer "employee_count", default: 0, null: false
    t.integer "conversation_count", default: 0, null: false
    t.integer "invited_count", default: 0, null: false
    t.integer "completed_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "company_profile", default: {}, null: false
    t.string "approval_status", default: "approved", null: false
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.jsonb "questionnaire_answers", default: {}, null: false
    t.datetime "questionnaire_completed_at"
    t.integer "questionnaire_step", default: 1, null: false
    t.datetime "docs_profile_stale_at"
    t.datetime "intelligence_updated_at"
    t.string "website_url"
    t.integer "questionnaire_version", default: 1, null: false
    t.index ["approval_status"], name: "index_companies_on_approval_status"
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "company_catalog_matches", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "solution_catalog_entry_id", null: false
    t.bigint "recommendation_id"
    t.float "score", default: 0.0, null: false
    t.text "why_it_fits"
    t.jsonb "evidence_used", default: [], null: false
    t.jsonb "assumptions", default: [], null: false
    t.jsonb "risks", default: [], null: false
    t.string "estimated_effort"
    t.text "validate_next"
    t.string "catalog_version"
    t.datetime "matched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "added_by_reviewer_id"
    t.index ["added_by_reviewer_id"], name: "index_company_catalog_matches_on_added_by_reviewer_id"
    t.index ["company_id", "solution_catalog_entry_id"], name: "idx_company_catalog_matches_unique", unique: true
    t.index ["company_id"], name: "index_company_catalog_matches_on_company_id"
    t.index ["recommendation_id"], name: "index_company_catalog_matches_on_recommendation_id"
    t.index ["solution_catalog_entry_id"], name: "index_company_catalog_matches_on_solution_catalog_entry_id"
  end

  create_table "company_clarification_questions", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "document_analysis_run_id"
    t.text "body", null: false
    t.string "status", default: "open", null: false
    t.text "answer"
    t.string "answer_source"
    t.jsonb "citations", default: [], null: false
    t.bigint "answered_by_company_user_id"
    t.bigint "dismissed_by_reviewer_user_id"
    t.datetime "answered_at"
    t.datetime "dismissed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "status"], name: "index_company_clarification_questions_on_company_id_and_status"
    t.index ["company_id"], name: "index_company_clarification_questions_on_company_id"
    t.index ["document_analysis_run_id"], name: "idx_on_document_analysis_run_id_0dfb5e96c7"
  end

  create_table "company_knowledge_entries", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "document_analysis_run_id"
    t.string "entry_type", default: "other", null: false
    t.string "title", null: false
    t.text "content", null: false
    t.float "confidence", default: 0.5, null: false
    t.string "department"
    t.string "status", default: "active", null: false
    t.string "content_hash"
    t.bigint "source_document_ids", default: [], null: false, array: true
    t.bigint "source_chunk_ids", default: [], null: false, array: true
    t.vector "embedding", limit: 768
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "content_hash"], name: "index_company_knowledge_entries_on_company_id_and_content_hash"
    t.index ["company_id", "entry_type"], name: "index_company_knowledge_entries_on_company_id_and_entry_type"
    t.index ["company_id", "status"], name: "index_company_knowledge_entries_on_company_id_and_status"
    t.index ["company_id"], name: "index_company_knowledge_entries_on_company_id"
    t.index ["document_analysis_run_id"], name: "index_company_knowledge_entries_on_document_analysis_run_id"
  end

  create_table "company_memory_facts", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "employee_id"
    t.bigint "conversation_id"
    t.string "fact_type", default: "finding", null: false
    t.string "department"
    t.text "content", null: false
    t.float "confidence"
    t.string "source_agent"
    t.vector "embedding", limit: 768
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "conversation_id, md5(content)", name: "index_memory_facts_on_conversation_and_content", unique: true
    t.index ["company_id", "department"], name: "index_company_memory_facts_on_company_id_and_department"
    t.index ["company_id", "fact_type"], name: "index_company_memory_facts_on_company_id_and_fact_type"
    t.index ["company_id"], name: "index_company_memory_facts_on_company_id"
    t.index ["conversation_id"], name: "index_company_memory_facts_on_conversation_id"
    t.index ["employee_id"], name: "index_company_memory_facts_on_employee_id"
  end

  create_table "company_registrations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "company_user_id", null: false
    t.bigint "reviewed_by_platform_user_id"
    t.string "company_name", null: false
    t.string "admin_name", null: false
    t.string "admin_email", null: false
    t.string "role_title"
    t.text "notes"
    t.string "status", default: "pending", null: false
    t.text "review_note"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "admin_phone"
    t.index ["admin_email"], name: "index_company_registrations_on_admin_email"
    t.index ["company_id"], name: "index_company_registrations_on_company_id"
    t.index ["company_user_id"], name: "index_company_registrations_on_company_user_id"
    t.index ["reviewed_by_platform_user_id"], name: "index_company_registrations_on_reviewed_by_platform_user_id"
    t.index ["status"], name: "index_company_registrations_on_status"
  end

  create_table "company_signals", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "label", null: false
    t.string "signal_type", null: false
    t.float "strength", default: 0.0, null: false
    t.string "departments", default: [], array: true
    t.integer "evidence_count", default: 1, null: false
    t.string "status", default: "emerging", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_updated_at", null: false
    t.jsonb "strength_history", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "signal_type", "label"], name: "index_company_signals_unique_label", unique: true
    t.index ["company_id"], name: "index_company_signals_on_company_id"
  end

  create_table "company_systems", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "category", default: "other", null: false
    t.string "source", default: "manual", null: false
    t.float "confidence", default: 1.0, null: false
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "active"], name: "index_company_systems_on_company_id_and_active"
    t.index ["company_id", "normalized_name"], name: "index_company_systems_on_company_id_and_normalized_name", unique: true
    t.index ["company_id"], name: "index_company_systems_on_company_id"
  end

  create_table "company_users", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "role", default: "company_admin", null: false
    t.string "status", default: "active", null: false
    t.bigint "invited_by_id"
    t.string "invitation_token"
    t.datetime "invitation_accepted_at"
    t.datetime "onboarding_completed_at"
    t.string "jti", null: false
    t.jsonb "notification_preferences", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "phone"
    t.index ["company_id", "email"], name: "index_company_users_on_company_id_and_email", unique: true
    t.index ["company_id"], name: "index_company_users_on_company_id"
    t.index ["invited_by_id"], name: "index_company_users_on_invited_by_id"
    t.index ["jti"], name: "index_company_users_on_jti", unique: true
  end

  create_table "consent_text_versions", force: :cascade do |t|
    t.string "version", null: false
    t.string "locale", default: "en", null: false
    t.text "body", null: false
    t.string "confirmation_keywords", default: ["YES", "I AGREE"], array: true
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["locale", "active"], name: "index_consent_text_versions_on_locale_and_active"
  end

  create_table "conversation_insights", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "employee_id", null: false
    t.bigint "company_id", null: false
    t.bigint "message_id"
    t.integer "turn_number", null: false
    t.string "insight_type", default: "turn_summary", null: false
    t.text "summary"
    t.jsonb "structured_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_conversation_insights_on_company_id"
    t.index ["conversation_id", "turn_number"], name: "index_conversation_insights_on_conversation_id_and_turn_number"
    t.index ["conversation_id"], name: "index_conversation_insights_on_conversation_id"
    t.index ["employee_id"], name: "index_conversation_insights_on_employee_id"
    t.index ["message_id"], name: "index_conversation_insights_on_message_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "company_id", null: false
    t.string "status", default: "onboarding", null: false
    t.uuid "langgraph_thread_id"
    t.integer "question_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "last_activity_at"
    t.datetime "abandoned_at"
    t.string "abandon_reason"
    t.jsonb "state_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_conversations_on_company_id"
    t.index ["employee_id"], name: "index_conversations_on_employee_id"
  end

  create_table "demo_requests", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "company_name", null: false
    t.string "role"
    t.text "notes"
    t.string "source", default: "marketing", null: false
    t.string "status", default: "new", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_demo_requests_on_email"
    t.index ["status"], name: "index_demo_requests_on_status"
  end

  create_table "discovery_playbooks", force: :cascade do |t|
    t.string "department", null: false
    t.integer "version", null: false
    t.text "prompt_block", null: false
    t.boolean "active", default: false, null: false
    t.text "notes"
    t.bigint "created_by_platform_user_id"
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_platform_user_id"], name: "index_discovery_playbooks_on_created_by_platform_user_id"
    t.index ["department", "active"], name: "index_discovery_playbooks_on_department_and_active"
  end

  create_table "discovery_question_feedbacks", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "message_id", null: false
    t.bigint "company_user_id", null: false
    t.string "feedback", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_discovery_question_feedbacks_on_company_id"
    t.index ["company_user_id"], name: "index_discovery_question_feedbacks_on_company_user_id"
    t.index ["message_id", "company_user_id"], name: "index_discovery_question_feedbacks_unique", unique: true
    t.index ["message_id"], name: "index_discovery_question_feedbacks_on_message_id"
  end

  create_table "document_analysis_events", force: :cascade do |t|
    t.bigint "document_analysis_run_id", null: false
    t.string "agent_name", null: false
    t.string "event_type", default: "step", null: false
    t.string "phase"
    t.text "message"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_analysis_run_id", "created_at"], name: "index_doc_analysis_events_on_run_and_created"
    t.index ["document_analysis_run_id"], name: "index_document_analysis_events_on_document_analysis_run_id"
  end

  create_table "document_analysis_runs", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "triggered_by_company_user_id"
    t.string "run_kind", default: "full", null: false
    t.string "status", default: "queued", null: false
    t.string "phase"
    t.string "model_tier", default: "fast"
    t.bigint "document_ids", default: [], null: false, array: true
    t.jsonb "profile_snapshot", default: {}, null: false
    t.jsonb "summary", default: {}, null: false
    t.jsonb "counters", default: {}, null: false
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "created_at"], name: "index_document_analysis_runs_on_company_id_and_created_at"
    t.index ["company_id", "status"], name: "index_document_analysis_runs_on_company_id_and_status"
    t.index ["company_id"], name: "index_document_analysis_runs_on_company_id"
    t.index ["company_id"], name: "index_document_analysis_runs_one_active_per_company", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying])::text[]))"
    t.index ["triggered_by_company_user_id"], name: "index_document_analysis_runs_on_triggered_by_company_user_id"
  end

  create_table "document_chunks", force: :cascade do |t|
    t.bigint "document_id", null: false
    t.integer "chunk_index", null: false
    t.text "content", null: false
    t.vector "embedding", limit: 768
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "chunk_index"], name: "index_document_chunks_on_document_id_and_chunk_index", unique: true
    t.index ["document_id"], name: "index_document_chunks_on_document_id"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "employee_id"
    t.bigint "conversation_id"
    t.bigint "message_id"
    t.bigint "uploaded_by_company_user_id"
    t.string "source", default: "company_portal_upload", null: false
    t.string "department"
    t.string "filename", null: false
    t.string "content_type"
    t.bigint "byte_size", default: 0, null: false
    t.string "storage_key", null: false
    t.string "status", default: "pending", null: false
    t.text "processing_error"
    t.jsonb "insights_preview", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "document_type"
    t.string "sensitivity", default: "internal"
    t.boolean "reviewer_visible", default: true, null: false
    t.date "effective_date"
    t.integer "version_number", default: 1, null: false
    t.datetime "retained_until"
    t.datetime "purged_at"
    t.index ["company_id", "status"], name: "index_documents_on_company_id_and_status"
    t.index ["company_id"], name: "index_documents_on_company_id"
    t.index ["conversation_id"], name: "index_documents_on_conversation_id"
    t.index ["employee_id"], name: "index_documents_on_employee_id"
    t.index ["message_id"], name: "index_documents_on_message_id"
    t.index ["uploaded_by_company_user_id"], name: "index_documents_on_uploaded_by_company_user_id"
  end

  create_table "employee_invitations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "employee_id", null: false
    t.bigint "company_user_id"
    t.string "phone_e164", null: false
    t.uuid "batch_id"
    t.string "whatsapp_template_name"
    t.string "delivery_status", default: "queued", null: false
    t.string "meta_message_id"
    t.datetime "sent_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_employee_invitations_on_company_id"
    t.index ["company_user_id"], name: "index_employee_invitations_on_company_user_id"
    t.index ["employee_id"], name: "index_employee_invitations_on_employee_id"
  end

  create_table "employee_market_alerts", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "company_id", null: false
    t.bigint "catalog_candidate_id", null: false
    t.float "fit_score", default: 0.0, null: false
    t.text "fit_rationale"
    t.jsonb "email_body", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.string "period_month", null: false
    t.datetime "sent_at"
    t.string "delivery_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_candidate_id"], name: "index_employee_market_alerts_on_catalog_candidate_id"
    t.index ["company_id"], name: "index_employee_market_alerts_on_company_id"
    t.index ["employee_id", "catalog_candidate_id"], name: "idx_employee_market_alerts_unique_candidate", unique: true
    t.index ["employee_id", "period_month"], name: "index_employee_market_alerts_on_employee_id_and_period_month"
    t.index ["employee_id"], name: "index_employee_market_alerts_on_employee_id"
    t.index ["status"], name: "index_employee_market_alerts_on_status"
  end

  create_table "employee_nudges", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "company_user_id"
    t.bigint "conversation_id"
    t.string "channel", default: "whatsapp_template", null: false
    t.string "meta_message_id"
    t.datetime "sent_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "delivery_status", default: "queued", null: false
    t.text "error_message"
    t.string "whatsapp_status"
    t.string "email_status"
    t.index ["company_user_id"], name: "index_employee_nudges_on_company_user_id"
    t.index ["conversation_id"], name: "index_employee_nudges_on_conversation_id"
    t.index ["employee_id"], name: "index_employee_nudges_on_employee_id"
  end

  create_table "employee_value_digests", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "company_id", null: false
    t.string "status", default: "draft", null: false
    t.string "period_key", null: false
    t.jsonb "content", default: {}, null: false
    t.jsonb "source_refs", default: [], null: false
    t.string "model_version"
    t.string "prompt_version"
    t.datetime "generated_at"
    t.datetime "reviewed_at"
    t.datetime "sent_at"
    t.datetime "opened_at"
    t.string "delivery_status"
    t.jsonb "feedback", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_employee_value_digests_on_company_id"
    t.index ["employee_id", "period_key"], name: "index_employee_value_digests_on_employee_id_and_period_key", unique: true
    t.index ["employee_id"], name: "index_employee_value_digests_on_employee_id"
  end

  create_table "employee_value_preferences", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.boolean "email_opt_in", default: false, null: false
    t.string "frequency", default: "monthly", null: false
    t.string "locale", default: "en"
    t.string "interests", default: [], array: true
    t.datetime "unsubscribed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_employee_value_preferences_on_employee_id", unique: true
  end

  create_table "employee_web_sessions", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "company_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "verified_at"
    t.datetime "last_seen_at"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_employee_web_sessions_on_company_id"
    t.index ["employee_id", "expires_at"], name: "index_employee_web_sessions_on_employee_id_and_expires_at"
    t.index ["employee_id"], name: "index_employee_web_sessions_on_employee_id"
    t.index ["token_digest"], name: "index_employee_web_sessions_on_token_digest", unique: true
  end

  create_table "employees", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "phone_e164", null: false
    t.string "display_name"
    t.string "department"
    t.string "role_title"
    t.string "seniority"
    t.string "preferred_language"
    t.string "participation_status", default: "invited", null: false
    t.string "onboarding_step", default: "awaiting_name", null: false
    t.datetime "consent_given_at"
    t.string "consent_text_version"
    t.datetime "invited_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "verified_at"
    t.datetime "last_active_at"
    t.datetime "last_nudged_at"
    t.bigint "invited_by_company_user_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email"
    t.string "preferred_channel", default: "whatsapp", null: false
    t.index ["company_id"], name: "index_employees_on_company_id"
    t.index ["email"], name: "index_employees_on_email", where: "(email IS NOT NULL)"
    t.index ["invited_by_company_user_id"], name: "index_employees_on_invited_by_company_user_id"
    t.index ["phone_e164"], name: "index_employees_on_phone_e164", unique: true
  end

  create_table "impersonation_sessions", force: :cascade do |t|
    t.bigint "platform_user_id", null: false
    t.bigint "company_user_id", null: false
    t.bigint "company_id", null: false
    t.string "token_jti", null: false
    t.datetime "expires_at", null: false
    t.datetime "ended_at"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_impersonation_sessions_on_company_id"
    t.index ["company_user_id"], name: "index_impersonation_sessions_on_company_user_id"
    t.index ["platform_user_id", "ended_at"], name: "index_impersonation_sessions_on_platform_user_id_and_ended_at"
    t.index ["platform_user_id"], name: "index_impersonation_sessions_on_platform_user_id"
    t.index ["token_jti"], name: "index_impersonation_sessions_on_token_jti", unique: true
  end

  create_table "insight_timeline_events", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "event_type", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.string "title", null: false
    t.text "summary"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "occurred_at"], name: "index_insight_timeline_events_on_company_id_and_occurred_at"
    t.index ["company_id"], name: "index_insight_timeline_events_on_company_id"
  end

  create_table "media_attachments", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "company_id", null: false
    t.bigint "employee_id", null: false
    t.bigint "conversation_id", null: false
    t.string "attachment_type", null: false
    t.string "mime_type"
    t.string "storage_key"
    t.string "meta_media_id"
    t.string "status", default: "pending", null: false
    t.text "extracted_text"
    t.text "processing_error"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "caption"
    t.jsonb "structured_insights", default: {}, null: false
    t.float "confidence"
    t.integer "duration_ms"
    t.string "language"
    t.bigint "document_id"
    t.index ["company_id"], name: "index_media_attachments_on_company_id"
    t.index ["conversation_id"], name: "index_media_attachments_on_conversation_id"
    t.index ["document_id"], name: "index_media_attachments_on_document_id"
    t.index ["employee_id"], name: "index_media_attachments_on_employee_id"
    t.index ["message_id"], name: "index_media_attachments_on_message_id"
    t.index ["meta_media_id"], name: "index_media_attachments_on_meta_media_id", unique: true, where: "(meta_media_id IS NOT NULL)"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "direction", null: false
    t.string "channel", default: "whatsapp", null: false
    t.string "message_type", null: false
    t.text "body"
    t.jsonb "raw_payload", default: {}, null: false
    t.string "external_id"
    t.string "processing_status", default: "ready", null: false
    t.boolean "is_discovery_question", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "reviewer_followup", default: false, null: false
    t.string "agent_id"
    t.jsonb "routing_decision", default: {}, null: false
    t.index ["agent_id"], name: "index_messages_on_agent_id", where: "(agent_id IS NOT NULL)"
    t.index ["conversation_id", "reviewer_followup", "created_at"], name: "index_messages_on_conversation_followup"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["external_id"], name: "index_messages_on_external_id", unique: true, where: "(external_id IS NOT NULL)"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "company_id"
    t.string "recipient_type", null: false
    t.bigint "recipient_id", null: false
    t.string "notification_type", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "action_url"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "read_at"
    t.datetime "emailed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_notifications_on_company_id"
    t.index ["recipient_type", "recipient_id"], name: "index_notifications_on_recipient_type_and_recipient_id"
  end

  create_table "patterns", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "title", null: false
    t.text "description"
    t.float "confidence", default: 0.0, null: false
    t.string "departments", default: [], array: true
    t.string "status", default: "emerging", null: false
    t.jsonb "linked_signal_ids", default: [], null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_updated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "title"], name: "index_patterns_on_company_id_and_title", unique: true
    t.index ["company_id"], name: "index_patterns_on_company_id"
  end

  create_table "platform_audit_logs", force: :cascade do |t|
    t.bigint "platform_user_id", null: false
    t.string "action", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_platform_audit_logs_on_created_at"
    t.index ["platform_user_id"], name: "index_platform_audit_logs_on_platform_user_id"
    t.index ["target_type", "target_id"], name: "index_platform_audit_logs_on_target_type_and_target_id"
  end

  create_table "platform_users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "role", default: "super_admin", null: false
    t.string "jti", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_platform_users_on_email", unique: true
    t.index ["jti"], name: "index_platform_users_on_jti", unique: true
  end

  create_table "recommendation_feedbacks", force: :cascade do |t|
    t.bigint "recommendation_id", null: false
    t.bigint "company_user_id", null: false
    t.string "feedback", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_user_id"], name: "index_recommendation_feedbacks_on_company_user_id"
    t.index ["recommendation_id"], name: "index_recommendation_feedbacks_on_recommendation_id"
  end

  create_table "recommendations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "implementation_outline"
    t.string "priority", default: "medium"
    t.string "status", default: "published", null: false
    t.jsonb "catalog_matches", default: [], null: false
    t.jsonb "related_signal_ids", default: [], null: false
    t.jsonb "related_pattern_ids", default: [], null: false
    t.string "company_feedback", default: "no_response", null: false
    t.text "company_feedback_note"
    t.datetime "company_feedback_at"
    t.bigint "company_feedback_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_feedback_by_id"], name: "index_recommendations_on_company_feedback_by_id"
    t.index ["company_id", "title"], name: "index_recommendations_on_company_id_and_title"
    t.index ["company_id"], name: "index_recommendations_on_company_id"
  end

  create_table "report_review_comments", force: :cascade do |t|
    t.bigint "report_review_id", null: false
    t.bigint "reviewer_user_id", null: false
    t.string "section_key", null: false
    t.text "body", null: false
    t.boolean "resolved", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_review_id", "section_key"], name: "index_report_review_comments_on_review_and_section"
    t.index ["report_review_id"], name: "index_report_review_comments_on_report_review_id"
    t.index ["reviewer_user_id"], name: "index_report_review_comments_on_reviewer_user_id"
  end

  create_table "report_review_findings", force: :cascade do |t|
    t.bigint "report_review_id", null: false
    t.bigint "reviewer_user_id", null: false
    t.string "finding_type", null: false
    t.string "section_key"
    t.string "target_type"
    t.bigint "target_id"
    t.string "disposition"
    t.string "severity", default: "info", null: false
    t.text "body", null: false
    t.jsonb "evidence_refs", default: [], null: false
    t.boolean "publishable", default: true, null: false
    t.string "resolution_status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_review_id", "finding_type"], name: "idx_on_report_review_id_finding_type_37d951f5e0"
    t.index ["report_review_id"], name: "index_report_review_findings_on_report_review_id"
    t.index ["reviewer_user_id"], name: "index_report_review_findings_on_reviewer_user_id"
  end

  create_table "report_review_section_states", force: :cascade do |t|
    t.bigint "report_review_id", null: false
    t.string "section_key", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_review_id", "section_key"], name: "index_report_review_section_states_unique", unique: true
    t.index ["report_review_id"], name: "index_report_review_section_states_on_report_review_id"
  end

  create_table "report_reviews", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "reviewer_user_id", null: false
    t.bigint "company_id", null: false
    t.string "status", default: "pending", null: false
    t.text "overall_note"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_report_reviews_on_company_id"
    t.index ["report_id", "reviewer_user_id"], name: "index_report_reviews_on_report_id_and_reviewer_user_id", unique: true
    t.index ["report_id"], name: "index_report_reviews_on_report_id"
    t.index ["reviewer_user_id"], name: "index_report_reviews_on_reviewer_user_id"
  end

  create_table "report_section_overrides", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "reviewer_user_id", null: false
    t.string "action", null: false
    t.string "section_key"
    t.string "anchor_section"
    t.string "title"
    t.text "body"
    t.integer "position", default: 0, null: false
    t.boolean "published", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id", "action"], name: "index_report_section_overrides_on_report_id_and_action"
    t.index ["report_id", "section_key"], name: "index_report_section_overrides_on_report_id_and_section_key"
    t.index ["report_id"], name: "index_report_section_overrides_on_report_id"
    t.index ["reviewer_user_id"], name: "index_report_section_overrides_on_reviewer_user_id"
  end

  create_table "report_share_accesses", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.string "share_token", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "accessed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_id", "accessed_at"], name: "index_report_share_accesses_on_report_id_and_accessed_at"
    t.index ["report_id"], name: "index_report_share_accesses_on_report_id"
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.integer "version", null: false
    t.bigint "previous_report_id"
    t.string "status", default: "queued", null: false
    t.string "visibility", default: "shared_with_company", null: false
    t.string "triggered_by_type", null: false
    t.bigint "triggered_by_id", null: false
    t.bigint "reviewed_by_platform_user_id"
    t.datetime "reviewed_at"
    t.string "storage_key"
    t.string "content_type", default: "application/pdf"
    t.jsonb "report_snapshot", default: {}, null: false
    t.string "share_token"
    t.datetime "share_token_expires_at"
    t.datetime "generated_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "review_workflow_status", default: "not_required", null: false
    t.datetime "reviews_completed_at"
    t.index ["company_id", "version"], name: "index_reports_on_company_id_and_version", unique: true
    t.index ["company_id"], name: "index_reports_on_company_id"
    t.index ["previous_report_id"], name: "index_reports_on_previous_report_id"
    t.index ["reviewed_by_platform_user_id"], name: "index_reports_on_reviewed_by_platform_user_id"
    t.index ["share_token"], name: "index_reports_on_share_token", unique: true, where: "(share_token IS NOT NULL)"
  end

  create_table "review_discussions", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "company_id", null: false
    t.bigint "author_reviewer_user_id", null: false
    t.bigint "target_reviewer_user_id"
    t.bigint "employee_id"
    t.bigint "conversation_id"
    t.bigint "parent_id"
    t.string "target_type", null: false
    t.string "anchor_type", null: false
    t.string "anchor_id", null: false
    t.text "body", null: false
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_reviewer_user_id"], name: "index_review_discussions_on_author_reviewer_user_id"
    t.index ["company_id"], name: "index_review_discussions_on_company_id"
    t.index ["conversation_id"], name: "index_review_discussions_on_conversation_id"
    t.index ["employee_id"], name: "index_review_discussions_on_employee_id"
    t.index ["parent_id"], name: "index_review_discussions_on_parent_id"
    t.index ["report_id", "anchor_type", "anchor_id"], name: "idx_review_discussions_report_anchor"
    t.index ["report_id", "parent_id"], name: "idx_review_discussions_report_parent"
    t.index ["report_id"], name: "index_review_discussions_on_report_id"
    t.index ["target_reviewer_user_id"], name: "index_review_discussions_on_target_reviewer_user_id"
  end

  create_table "reviewer_assignments", force: :cascade do |t|
    t.bigint "reviewer_user_id", null: false
    t.bigint "company_id", null: false
    t.bigint "assigned_by_platform_user_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "assigned_at", null: false
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_by_platform_user_id"], name: "index_reviewer_assignments_on_assigned_by_platform_user_id"
    t.index ["company_id", "reviewer_user_id"], name: "index_reviewer_assignments_active_unique", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["company_id"], name: "index_reviewer_assignments_on_company_id"
    t.index ["reviewer_user_id"], name: "index_reviewer_assignments_on_reviewer_user_id"
  end

  create_table "reviewer_chat_messages", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "sender_reviewer_user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "created_at"], name: "index_reviewer_chat_messages_on_company_id_and_created_at"
    t.index ["company_id"], name: "index_reviewer_chat_messages_on_company_id"
    t.index ["sender_reviewer_user_id"], name: "index_reviewer_chat_messages_on_sender_reviewer_user_id"
  end

  create_table "reviewer_experiences", force: :cascade do |t|
    t.bigint "reviewer_user_id", null: false
    t.string "organization", null: false
    t.string "title", null: false
    t.integer "start_year", null: false
    t.integer "end_year"
    t.string "summary", limit: 200
    t.integer "sort_order", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewer_user_id", "sort_order"], name: "index_reviewer_experiences_on_reviewer_user_id_and_sort_order"
    t.index ["reviewer_user_id"], name: "index_reviewer_experiences_on_reviewer_user_id"
  end

  create_table "reviewer_info_replies", force: :cascade do |t|
    t.bigint "reviewer_info_request_id", null: false
    t.bigint "message_id", null: false
    t.text "body", null: false
    t.datetime "received_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_reviewer_info_replies_on_message_id"
    t.index ["reviewer_info_request_id"], name: "index_reviewer_info_replies_on_reviewer_info_request_id"
  end

  create_table "reviewer_info_requests", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "report_id"
    t.bigint "reviewer_user_id", null: false
    t.bigint "employee_id", null: false
    t.bigint "conversation_id", null: false
    t.text "body", null: false
    t.string "status", default: "draft", null: false
    t.string "meta_message_id"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "message_id"
    t.bigint "review_discussion_id"
    t.index ["company_id"], name: "index_reviewer_info_requests_on_company_id"
    t.index ["conversation_id"], name: "index_reviewer_info_requests_on_conversation_id"
    t.index ["employee_id", "status"], name: "index_reviewer_info_requests_awaiting_reply", where: "((status)::text = 'awaiting_reply'::text)"
    t.index ["employee_id"], name: "index_reviewer_info_requests_on_employee_id"
    t.index ["message_id"], name: "index_reviewer_info_requests_on_message_id"
    t.index ["report_id"], name: "index_reviewer_info_requests_on_report_id"
    t.index ["review_discussion_id"], name: "index_reviewer_info_requests_on_review_discussion_id"
    t.index ["reviewer_user_id"], name: "index_reviewer_info_requests_on_reviewer_user_id"
  end

  create_table "reviewer_outreach_replies", force: :cascade do |t|
    t.bigint "reviewer_outreach_id", null: false
    t.string "channel", null: false
    t.text "body", null: false
    t.bigint "message_id"
    t.bigint "company_user_id"
    t.datetime "received_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewer_outreach_id"], name: "index_reviewer_outreach_replies_on_reviewer_outreach_id"
  end

  create_table "reviewer_outreaches", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "report_id"
    t.bigint "reviewer_user_id", null: false
    t.string "recipient_type", null: false
    t.bigint "recipient_id"
    t.bigint "employee_id"
    t.bigint "conversation_id"
    t.string "purpose", default: "clarification", null: false
    t.string "channel", default: "whatsapp", null: false
    t.string "status", default: "draft", null: false
    t.text "body", null: false
    t.text "reason"
    t.string "section_key"
    t.string "anchor_type"
    t.string "anchor_id"
    t.datetime "requested_deadline_at"
    t.bigint "approved_by_company_user_id"
    t.datetime "approved_at"
    t.datetime "declined_at"
    t.text "admin_note"
    t.text "edited_body"
    t.string "reply_token_digest"
    t.datetime "sent_at"
    t.string "meta_message_id"
    t.bigint "message_id"
    t.bigint "reviewer_info_request_id"
    t.jsonb "audit_trail", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_reviewer_outreaches_on_company_id"
    t.index ["conversation_id"], name: "index_reviewer_outreaches_on_conversation_id"
    t.index ["employee_id"], name: "index_reviewer_outreaches_on_employee_id"
    t.index ["reply_token_digest"], name: "index_reviewer_outreaches_on_reply_token_digest", unique: true, where: "(reply_token_digest IS NOT NULL)"
    t.index ["report_id"], name: "index_reviewer_outreaches_on_report_id"
    t.index ["reviewer_user_id"], name: "index_reviewer_outreaches_on_reviewer_user_id"
    t.index ["status"], name: "index_reviewer_outreaches_on_status"
  end

  create_table "reviewer_users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.string "jti", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "avatar_storage_key"
    t.string "headline", limit: 120
    t.text "bio"
    t.string "linkedin_url"
    t.string "website_url"
    t.string "location"
    t.string "timezone"
    t.string "languages", default: [], null: false, array: true
    t.string "expertise_tags", default: [], null: false, array: true
    t.string "industries", default: [], null: false, array: true
    t.integer "years_experience"
    t.jsonb "credentials", default: [], null: false
    t.string "profile_status", default: "draft", null: false
    t.datetime "profile_completed_at"
    t.datetime "platform_verified_at"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.text "application_notes"
    t.text "expertise_summary"
    t.jsonb "questionnaire_answers", default: {}, null: false
    t.integer "questionnaire_step", default: 1, null: false
    t.datetime "questionnaire_completed_at"
    t.string "cv_storage_key"
    t.index ["email"], name: "index_reviewer_users_on_email", unique: true
    t.index ["jti"], name: "index_reviewer_users_on_jti", unique: true
    t.index ["profile_status"], name: "index_reviewer_users_on_profile_status"
  end

  create_table "solution_catalog", force: :cascade do |t|
    t.string "name", null: false
    t.string "vendor"
    t.string "category", null: false
    t.text "description"
    t.string "website_url"
    t.string "tags", default: [], array: true
    t.string "match_keywords", default: [], array: true
    t.boolean "active", default: true, null: false
    t.string "partnership_tier", default: "none"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.string "entity_type", default: "tool"
    t.string "use_cases", default: [], array: true
    t.string "capabilities", default: [], array: true
    t.string "required_systems", default: [], array: true
    t.string "deployment_model"
    t.string "industries", default: [], array: true
    t.string "departments", default: [], array: true
    t.string "role_relevance", default: [], array: true
    t.string "maturity"
    t.string "security_notes"
    t.text "pricing_summary"
    t.text "limitations"
    t.string "evidence_urls", default: [], array: true
    t.bigint "owned_by_platform_user_id"
    t.datetime "published_at"
    t.datetime "last_verified_at"
    t.jsonb "match_profile", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.vector "embedding", limit: 768
    t.boolean "first_party", default: false, null: false
    t.index ["slug"], name: "index_solution_catalog_on_slug", unique: true, where: "(slug IS NOT NULL)"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "plan", default: "trial", null: false
    t.string "status", default: "trial", null: false
    t.datetime "trial_ends_at"
    t.datetime "current_period_ends_at"
    t.integer "conversation_limit"
    t.integer "conversations_used", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_subscriptions_on_company_id", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "provider", default: "meta_whatsapp", null: false
    t.string "external_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "received", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_webhook_events_on_external_id", unique: true
  end

  create_table "whatsapp_delivery_metrics", force: :cascade do |t|
    t.datetime "hour_bucket", null: false
    t.string "metric_type", null: false
    t.integer "count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hour_bucket", "metric_type"], name: "index_whatsapp_metrics_on_hour_and_type", unique: true
  end

  add_foreign_key "agentic_ideas", "companies"
  add_foreign_key "agentic_ideas", "solution_catalog", column: "solution_catalog_entry_id"
  add_foreign_key "catalog_candidates", "catalog_source_records"
  add_foreign_key "catalog_candidates", "solution_catalog", column: "suggested_catalog_entry_id"
  add_foreign_key "catalog_endorsements", "companies"
  add_foreign_key "catalog_endorsements", "reports"
  add_foreign_key "catalog_endorsements", "reviewer_users"
  add_foreign_key "catalog_endorsements", "solution_catalog", column: "solution_catalog_entry_id"
  add_foreign_key "catalog_entry_aliases", "solution_catalog", column: "solution_catalog_entry_id"
  add_foreign_key "catalog_pricing_snapshots", "solution_catalog", column: "solution_catalog_entry_id"
  add_foreign_key "catalog_source_records", "catalog_sources"
  add_foreign_key "catalog_source_records", "catalog_sync_runs"
  add_foreign_key "catalog_sync_runs", "catalog_sources"
  add_foreign_key "company_catalog_matches", "companies"
  add_foreign_key "company_catalog_matches", "recommendations"
  add_foreign_key "company_catalog_matches", "reviewer_users", column: "added_by_reviewer_id"
  add_foreign_key "company_catalog_matches", "solution_catalog", column: "solution_catalog_entry_id"
  add_foreign_key "company_clarification_questions", "companies"
  add_foreign_key "company_clarification_questions", "company_users", column: "answered_by_company_user_id"
  add_foreign_key "company_clarification_questions", "document_analysis_runs"
  add_foreign_key "company_clarification_questions", "reviewer_users", column: "dismissed_by_reviewer_user_id"
  add_foreign_key "company_knowledge_entries", "companies"
  add_foreign_key "company_knowledge_entries", "document_analysis_runs"
  add_foreign_key "company_memory_facts", "companies"
  add_foreign_key "company_memory_facts", "conversations"
  add_foreign_key "company_memory_facts", "employees"
  add_foreign_key "company_registrations", "companies"
  add_foreign_key "company_registrations", "company_users"
  add_foreign_key "company_registrations", "platform_users", column: "reviewed_by_platform_user_id"
  add_foreign_key "company_signals", "companies"
  add_foreign_key "company_systems", "companies"
  add_foreign_key "company_users", "companies"
  add_foreign_key "company_users", "company_users", column: "invited_by_id"
  add_foreign_key "conversation_insights", "companies"
  add_foreign_key "conversation_insights", "conversations"
  add_foreign_key "conversation_insights", "employees"
  add_foreign_key "conversation_insights", "messages"
  add_foreign_key "conversations", "companies"
  add_foreign_key "conversations", "employees"
  add_foreign_key "discovery_playbooks", "platform_users", column: "created_by_platform_user_id"
  add_foreign_key "discovery_question_feedbacks", "companies"
  add_foreign_key "discovery_question_feedbacks", "company_users"
  add_foreign_key "discovery_question_feedbacks", "messages"
  add_foreign_key "document_analysis_events", "document_analysis_runs"
  add_foreign_key "document_analysis_runs", "companies"
  add_foreign_key "document_analysis_runs", "company_users", column: "triggered_by_company_user_id"
  add_foreign_key "document_chunks", "documents"
  add_foreign_key "documents", "companies"
  add_foreign_key "documents", "company_users", column: "uploaded_by_company_user_id"
  add_foreign_key "documents", "conversations"
  add_foreign_key "documents", "employees"
  add_foreign_key "documents", "messages"
  add_foreign_key "employee_invitations", "companies"
  add_foreign_key "employee_invitations", "company_users"
  add_foreign_key "employee_invitations", "employees"
  add_foreign_key "employee_market_alerts", "catalog_candidates"
  add_foreign_key "employee_market_alerts", "companies"
  add_foreign_key "employee_market_alerts", "employees"
  add_foreign_key "employee_nudges", "company_users"
  add_foreign_key "employee_nudges", "conversations"
  add_foreign_key "employee_nudges", "employees"
  add_foreign_key "employee_value_digests", "companies"
  add_foreign_key "employee_value_digests", "employees"
  add_foreign_key "employee_value_preferences", "employees"
  add_foreign_key "employee_web_sessions", "companies"
  add_foreign_key "employee_web_sessions", "employees"
  add_foreign_key "employees", "companies"
  add_foreign_key "employees", "company_users", column: "invited_by_company_user_id"
  add_foreign_key "impersonation_sessions", "companies"
  add_foreign_key "impersonation_sessions", "company_users"
  add_foreign_key "impersonation_sessions", "platform_users"
  add_foreign_key "insight_timeline_events", "companies"
  add_foreign_key "media_attachments", "companies"
  add_foreign_key "media_attachments", "conversations"
  add_foreign_key "media_attachments", "documents"
  add_foreign_key "media_attachments", "employees"
  add_foreign_key "media_attachments", "messages"
  add_foreign_key "messages", "conversations"
  add_foreign_key "notifications", "companies"
  add_foreign_key "patterns", "companies"
  add_foreign_key "platform_audit_logs", "platform_users"
  add_foreign_key "recommendation_feedbacks", "company_users"
  add_foreign_key "recommendation_feedbacks", "recommendations"
  add_foreign_key "recommendations", "companies"
  add_foreign_key "recommendations", "company_users", column: "company_feedback_by_id"
  add_foreign_key "report_review_comments", "report_reviews"
  add_foreign_key "report_review_comments", "reviewer_users"
  add_foreign_key "report_review_findings", "report_reviews"
  add_foreign_key "report_review_findings", "reviewer_users"
  add_foreign_key "report_review_section_states", "report_reviews"
  add_foreign_key "report_reviews", "companies"
  add_foreign_key "report_reviews", "reports"
  add_foreign_key "report_reviews", "reviewer_users"
  add_foreign_key "report_section_overrides", "reports"
  add_foreign_key "report_section_overrides", "reviewer_users"
  add_foreign_key "report_share_accesses", "reports"
  add_foreign_key "reports", "companies"
  add_foreign_key "reports", "platform_users", column: "reviewed_by_platform_user_id"
  add_foreign_key "reports", "reports", column: "previous_report_id"
  add_foreign_key "review_discussions", "companies"
  add_foreign_key "review_discussions", "conversations"
  add_foreign_key "review_discussions", "employees"
  add_foreign_key "review_discussions", "reports"
  add_foreign_key "review_discussions", "review_discussions", column: "parent_id"
  add_foreign_key "review_discussions", "reviewer_users", column: "author_reviewer_user_id"
  add_foreign_key "review_discussions", "reviewer_users", column: "target_reviewer_user_id"
  add_foreign_key "reviewer_assignments", "companies"
  add_foreign_key "reviewer_assignments", "platform_users", column: "assigned_by_platform_user_id"
  add_foreign_key "reviewer_assignments", "reviewer_users"
  add_foreign_key "reviewer_chat_messages", "companies"
  add_foreign_key "reviewer_chat_messages", "reviewer_users", column: "sender_reviewer_user_id"
  add_foreign_key "reviewer_experiences", "reviewer_users"
  add_foreign_key "reviewer_info_replies", "messages"
  add_foreign_key "reviewer_info_replies", "reviewer_info_requests"
  add_foreign_key "reviewer_info_requests", "companies"
  add_foreign_key "reviewer_info_requests", "conversations"
  add_foreign_key "reviewer_info_requests", "employees"
  add_foreign_key "reviewer_info_requests", "messages"
  add_foreign_key "reviewer_info_requests", "reports"
  add_foreign_key "reviewer_info_requests", "review_discussions"
  add_foreign_key "reviewer_info_requests", "reviewer_users"
  add_foreign_key "reviewer_outreach_replies", "reviewer_outreaches"
  add_foreign_key "reviewer_outreaches", "companies"
  add_foreign_key "reviewer_outreaches", "company_users", column: "approved_by_company_user_id"
  add_foreign_key "reviewer_outreaches", "conversations"
  add_foreign_key "reviewer_outreaches", "employees"
  add_foreign_key "reviewer_outreaches", "reports"
  add_foreign_key "reviewer_outreaches", "reviewer_users"
  add_foreign_key "subscriptions", "companies"
end
