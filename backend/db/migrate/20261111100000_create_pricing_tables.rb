# frozen_string_literal: true

# What Stage 1 pricing records (Doc 06 §10, Doc 17 §14). Rate cards and margin
# floors are versioned and never edited: a change is a new version, with who
# made it and why (Doc 17 §8.3). A quote is never overwritten either — an
# adjustment, new inputs or a changed plan make a new version that supersedes
# it (Doc 06 §1.2) — and everything that happens to one is kept as an event
# (Doc 17 §18).
class CreatePricingTables < ActiveRecord::Migration[7.1]
  def change
    create_table :rate_card_versions do |t|
      t.integer :version, null: false
      t.datetime :effective_from, null: false
      t.string :currency, null: false, default: "AED"
      t.jsonb :rates, null: false, default: {}
      t.jsonb :stage1, null: false, default: {}
      t.boolean :placeholder, null: false, default: false
      t.text :reason, null: false
      t.references :changed_by, polymorphic: true
      t.datetime :created_at, null: false
    end
    add_index :rate_card_versions, :version, unique: true

    create_table :margin_floor_versions do |t|
      t.integer :version, null: false
      t.decimal :value, precision: 5, scale: 4, null: false
      t.datetime :effective_from, null: false
      t.text :reason, null: false
      t.references :changed_by, polymorphic: true
      t.datetime :created_at, null: false
    end
    add_index :margin_floor_versions, :version, unique: true

    create_table :quotes do |t|
      t.references :engagement, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :quote_stage, null: false
      t.integer :version, null: false
      t.references :parent_quote, foreign_key: { to_table: :quotes }
      t.string :status, null: false, default: "PROPOSED"
      t.string :currency, null: false
      t.references :rate_card_version, null: false, foreign_key: true
      t.references :margin_floor_version, null: false, foreign_key: true

      # Fixed when the quote is made.
      t.jsonb :inputs, null: false, default: {}
      t.jsonb :estimate, null: false, default: {}
      t.jsonb :line_items, null: false, default: []
      t.decimal :subtotal, precision: 12, scale: 2, null: false
      t.decimal :tax_rate, precision: 5, scale: 4, null: false, default: 0
      t.decimal :tax_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total, precision: 12, scale: 2, null: false
      t.decimal :additional_participant_rate, precision: 12, scale: 2, null: false
      t.integer :participants_included, null: false
      t.integer :deep_dives_included, null: false
      t.jsonb :internal, null: false, default: {}
      t.decimal :margin_percent, precision: 6, scale: 2, null: false
      t.boolean :below_floor, null: false, default: false
      t.date :valid_until

      # Written alongside: the explanation for the administrator and the scope
      # statement for the client (P24, or the template when P24 can't be used).
      t.jsonb :admin_explanation, null: false, default: {}
      t.jsonb :client_scope, null: false, default: {}
      t.string :explanation_source, null: false, default: "TEMPLATE"

      t.references :approved_by, foreign_key: { to_table: :platform_users }
      t.datetime :approved_at
      t.datetime :issued_at
      t.datetime :first_viewed_at
      t.references :accepted_by, foreign_key: { to_table: :company_users }
      t.datetime :accepted_at
      t.references :declined_by, foreign_key: { to_table: :company_users }
      t.datetime :declined_at
      t.text :decline_reason
      t.references :rejected_by, foreign_key: { to_table: :platform_users }
      t.datetime :rejected_at
      t.text :rejection_note
      t.string :pdf_storage_key
      t.timestamps
    end
    add_index :quotes, %i[engagement_id quote_stage version], unique: true
    add_index :quotes, :status
    # One quote at a time is with the administrator or the client, and an
    # engagement accepts one Stage 1 quote.
    add_index :quotes, %i[engagement_id quote_stage], unique: true, where: "status IN ('PROPOSED', 'ISSUED')",
                                                      name: "index_quotes_one_open_per_stage"
    add_index :quotes, %i[engagement_id quote_stage], unique: true, where: "status = 'ACCEPTED'",
                                                      name: "index_quotes_one_accepted_per_stage"

    create_table :estimate_overrides do |t|
      t.references :quote, null: false, foreign_key: true
      t.string :kind, null: false
      t.decimal :original_total, precision: 12, scale: 2, null: false
      t.decimal :adjusted_total, precision: 12, scale: 2, null: false
      t.string :structured_reason, null: false
      t.text :free_text
      t.references :actor, null: false, foreign_key: { to_table: :platform_users }
      t.datetime :created_at, null: false
    end

    create_table :quote_events do |t|
      t.references :quote, null: false, foreign_key: true
      t.string :event, null: false
      t.references :actor, polymorphic: true
      t.jsonb :detail, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :quote_events, %i[quote_id event]

    # Doc 17 §10.2: currency per engagement, AED by default.
    add_column :engagements, :currency, :string, null: false, default: "AED"
  end
end
