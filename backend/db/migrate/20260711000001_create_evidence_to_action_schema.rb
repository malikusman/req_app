# frozen_string_literal: true

class CreateEvidenceToActionSchema < ActiveRecord::Migration[7.1]
  def change
    # --- Phase 0 / 4: document metadata + retention ---
    change_table :documents, bulk: true do |t|
      t.string :document_type
      t.string :sensitivity, default: "internal"
      t.boolean :reviewer_visible, default: true, null: false
      t.date :effective_date
      t.integer :version_number, default: 1, null: false
      t.datetime :retained_until
      t.datetime :purged_at
    end

    # --- Phase 3: structured reviewer findings ---
    create_table :report_review_findings do |t|
      t.references :report_review, null: false, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.string :finding_type, null: false
      t.string :section_key
      t.string :target_type
      t.bigint :target_id
      t.string :disposition
      t.string :severity, default: "info", null: false
      t.text :body, null: false
      t.jsonb :evidence_refs, default: [], null: false
      t.boolean :publishable, default: true, null: false
      t.string :resolution_status, default: "open", null: false
      t.timestamps
    end
    add_index :report_review_findings, %i[report_review_id finding_type]

    # --- Phase 1: admin-gated outreach ---
    create_table :reviewer_outreaches do |t|
      t.references :company, null: false, foreign_key: true
      t.references :report, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.string :recipient_type, null: false
      t.bigint :recipient_id
      t.references :employee, foreign_key: true
      t.references :conversation, foreign_key: true
      t.string :purpose, default: "clarification", null: false
      t.string :channel, default: "whatsapp", null: false
      t.string :status, default: "draft", null: false
      t.text :body, null: false
      t.text :reason
      t.string :section_key
      t.string :anchor_type
      t.string :anchor_id
      t.datetime :requested_deadline_at
      t.bigint :approved_by_company_user_id
      t.datetime :approved_at
      t.datetime :declined_at
      t.text :admin_note
      t.text :edited_body
      t.string :reply_token_digest
      t.datetime :sent_at
      t.string :meta_message_id
      t.bigint :message_id
      t.bigint :reviewer_info_request_id
      t.jsonb :audit_trail, default: [], null: false
      t.timestamps
    end
    add_index :reviewer_outreaches, :status
    add_index :reviewer_outreaches, :reply_token_digest, unique: true, where: "reply_token_digest IS NOT NULL"
    add_foreign_key :reviewer_outreaches, :company_users, column: :approved_by_company_user_id

    create_table :reviewer_outreach_replies do |t|
      t.references :reviewer_outreach, null: false, foreign_key: true
      t.string :channel, null: false
      t.text :body, null: false
      t.bigint :message_id
      t.bigint :company_user_id
      t.datetime :received_at, null: false
      t.timestamps
    end

    # --- Phase 5/6: catalog enrichment + market discovery ---
    change_table :solution_catalog, bulk: true do |t|
      t.string :slug
      t.string :entity_type, default: "tool"
      t.string :use_cases, default: [], array: true
      t.string :capabilities, default: [], array: true
      t.string :required_systems, default: [], array: true
      t.string :deployment_model
      t.string :industries, default: [], array: true
      t.string :departments, default: [], array: true
      t.string :role_relevance, default: [], array: true
      t.string :maturity
      t.string :security_notes
      t.text :pricing_summary
      t.text :limitations
      t.string :evidence_urls, default: [], array: true
      t.bigint :owned_by_platform_user_id
      t.datetime :published_at
      t.datetime :last_verified_at
      t.jsonb :match_profile, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
    end
    add_column :solution_catalog, :embedding, :vector, limit: 1536
    add_index :solution_catalog, :slug, unique: true, where: "slug IS NOT NULL"

    create_table :catalog_sources do |t|
      t.string :name, null: false
      t.string :source_type, null: false
      t.string :endpoint_url
      t.string :sync_cron
      t.datetime :last_sync_at
      t.string :last_sync_status
      t.integer :trust_score, default: 50, null: false
      t.boolean :active, default: true, null: false
      t.jsonb :config, default: {}, null: false
      t.timestamps
    end

    create_table :catalog_sync_runs do |t|
      t.references :catalog_source, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :status, default: "running", null: false
      t.integer :records_fetched, default: 0, null: false
      t.integer :candidates_created, default: 0, null: false
      t.integer :embedding_calls, default: 0, null: false
      t.integer :llm_tokens, default: 0, null: false
      t.jsonb :errors, default: [], null: false
      t.jsonb :budget, default: {}, null: false
      t.timestamps
    end

    create_table :catalog_source_records do |t|
      t.references :catalog_source, null: false, foreign_key: true
      t.references :catalog_sync_run, foreign_key: true
      t.string :external_id, null: false
      t.string :fingerprint, null: false
      t.string :title
      t.string :url
      t.jsonb :raw_payload, default: {}, null: false
      t.datetime :fetched_at, null: false
      t.string :parse_status, default: "pending", null: false
      t.timestamps
    end
    add_index :catalog_source_records, %i[catalog_source_id external_id], unique: true, name: "idx_catalog_source_records_unique_external"

    create_table :catalog_candidates do |t|
      t.references :catalog_source_record, foreign_key: true
      t.string :name, null: false
      t.string :vendor
      t.string :entity_type, default: "tool", null: false
      t.text :description
      t.string :website_url
      t.float :confidence, default: 0.0, null: false
      t.string :review_status, default: "pending", null: false
      t.bigint :suggested_catalog_entry_id
      t.bigint :reviewed_by_platform_user_id
      t.datetime :reviewed_at
      t.text :review_note
      t.jsonb :provenance, default: {}, null: false
      t.timestamps
    end
    add_index :catalog_candidates, :review_status
    add_foreign_key :catalog_candidates, :solution_catalog, column: :suggested_catalog_entry_id

    create_table :catalog_entry_aliases do |t|
      t.references :solution_catalog_entry, null: false, foreign_key: { to_table: :solution_catalog }
      t.string :alias_text, null: false
      t.string :normalized_alias, null: false
      t.timestamps
    end
    add_index :catalog_entry_aliases, :normalized_alias

    create_table :catalog_pricing_snapshots do |t|
      t.references :solution_catalog_entry, null: false, foreign_key: { to_table: :solution_catalog }
      t.string :pricing_model
      t.string :currency
      t.string :unit
      t.decimal :amount, precision: 12, scale: 2
      t.datetime :effective_at
      t.string :source_url
      t.text :raw_text
      t.timestamps
    end

    # --- Phase 7: company catalog fit + reviewer endorsements ---
    create_table :company_catalog_matches do |t|
      t.references :company, null: false, foreign_key: true
      t.references :solution_catalog_entry, null: false, foreign_key: { to_table: :solution_catalog }
      t.references :recommendation, foreign_key: true
      t.float :score, default: 0.0, null: false
      t.text :why_it_fits
      t.jsonb :evidence_used, default: [], null: false
      t.jsonb :assumptions, default: [], null: false
      t.jsonb :risks, default: [], null: false
      t.string :estimated_effort
      t.text :validate_next
      t.string :catalog_version
      t.datetime :matched_at, null: false
      t.timestamps
    end
    add_index :company_catalog_matches, %i[company_id solution_catalog_entry_id], name: "idx_company_catalog_matches_unique", unique: true

    create_table :catalog_endorsements do |t|
      t.references :company, null: false, foreign_key: true
      t.references :report, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.references :solution_catalog_entry, foreign_key: { to_table: :solution_catalog }
      t.string :disposition, null: false
      t.text :rationale
      t.string :source_url
      t.boolean :publishable, default: true, null: false
      t.timestamps
    end

    # --- Phase 8: employee value digests ---
    create_table :employee_value_preferences do |t|
      t.references :employee, null: false, foreign_key: true, index: { unique: true }
      t.boolean :email_opt_in, default: false, null: false
      t.string :frequency, default: "monthly", null: false
      t.string :locale, default: "en"
      t.string :interests, default: [], array: true
      t.datetime :unsubscribed_at
      t.timestamps
    end

    create_table :employee_value_digests do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :status, default: "draft", null: false
      t.string :period_key, null: false
      t.jsonb :content, default: {}, null: false
      t.jsonb :source_refs, default: [], null: false
      t.string :model_version
      t.string :prompt_version
      t.datetime :generated_at
      t.datetime :reviewed_at
      t.datetime :sent_at
      t.datetime :opened_at
      t.string :delivery_status
      t.jsonb :feedback, default: {}, null: false
      t.timestamps
    end
    add_index :employee_value_digests, %i[employee_id period_key], unique: true

    # --- Phase 9: meeting requests ---
    create_table :meeting_requests do |t|
      t.references :company, null: false, foreign_key: true
      t.references :report, foreign_key: true
      t.references :reviewer_user, null: false, foreign_key: true
      t.references :reviewer_outreach, foreign_key: true
      t.text :purpose, null: false
      t.string :desired_roles, default: [], array: true
      t.integer :duration_minutes, default: 30
      t.string :urgency, default: "normal"
      t.jsonb :proposed_windows, default: [], null: false
      t.string :status, default: "pending_admin", null: false
      t.bigint :approved_by_company_user_id
      t.jsonb :selected_participant_ids, default: [], null: false
      t.datetime :scheduled_at
      t.string :meeting_link
      t.text :admin_note
      t.text :outcome_note
      t.jsonb :audit_trail, default: [], null: false
      t.timestamps
    end
    add_foreign_key :meeting_requests, :company_users, column: :approved_by_company_user_id

    # Vector indexes for document chunks (hnsw when available)
    # Neighbor gem works without HNSW; add btree-friendly path via existing FKs.
  end
end
