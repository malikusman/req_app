# frozen_string_literal: true

# Values read from the client's website, proposed for confirmation (Doc 06 §3.3,
# Doc 07 §5). A candidate is never a fact: only confirming or correcting it
# writes to the company profile.
class CreatePrefillCandidates < ActiveRecord::Migration[7.1]
  def change
    create_table :prefill_candidates do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.string :target_field, null: false
      t.jsonb :value, null: false
      t.text :display_text
      t.string :confidence, null: false
      t.string :source_url, null: false
      t.text :evidence_excerpt, null: false
      t.string :status, null: false, default: "PROPOSED"
      t.string :website_url, null: false
      t.string :prompt_version, null: false
      t.datetime :extracted_at, null: false
      t.references :decided_by, polymorphic: true
      t.datetime :decided_at
      t.timestamps
    end
    add_index :prefill_candidates, %i[engagement_id status]

    change_table :engagements, bulk: true do |t|
      t.string :prefill_status, null: false, default: "not_started"
      t.string :prefill_error
      t.text :prefill_entity_note
      t.datetime :prefill_finished_at
    end
  end
end
