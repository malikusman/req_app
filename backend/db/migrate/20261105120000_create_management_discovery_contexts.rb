# frozen_string_literal: true

# What a conversation with leadership produced (Doc 08 §15–16, Doc 06 §5.1–5.4):
# one person's view of the business, the issues and ambitions they raised, and
# the changes already planned. Each finished session adds a new version; nothing
# is overwritten.
#
# All of it is MANAGEMENT_STRATEGIC: consultants and later analysis read it;
# employees and their interviews never do. consultant_private (political context,
# notes) is CONSULTANT_PRIVATE and is only ever serialised for consultants.
class CreateManagementDiscoveryContexts < ActiveRecord::Migration[7.1]
  def change
    create_table :management_discovery_contexts do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :engagement_participant, null: false, foreign_key: true, index: false
      t.references :conversation_session, null: false, foreign_key: true, index: { unique: true }
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false
      t.string :persona
      t.string :scope
      t.string :schema_version, null: false
      t.string :prompt_version
      t.jsonb :content, null: false, default: {}
      t.jsonb :neutral_employee_context, null: false, default: []
      t.jsonb :unknowns, null: false, default: []
      t.jsonb :contradictions, null: false, default: []
      t.jsonb :completion, null: false, default: {}
      t.jsonb :coverage_state, null: false, default: {}
      t.jsonb :consultant_private, null: false, default: {}
      t.string :fallback_reason
      t.timestamps
    end
    add_index :management_discovery_contexts, %i[engagement_participant_id version], unique: true

    create_table :strategic_findings do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :management_discovery_context, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false, default: "ACTIVE"
      t.string :category, null: false
      t.string :scope, null: false
      t.text :statement, null: false
      t.text :business_consequence
      t.string :symptom_or_cause
      t.string :source_basis, null: false
      t.string :fact_status, null: false
      t.string :management_importance
      t.string :related_departments, array: true, null: false, default: []
      t.string :related_systems, array: true, null: false, default: []
      t.text :planned_initiative_link
      t.text :validation_need
      t.string :evidence, array: true, null: false, default: []
      t.string :edited_by_type
      t.bigint :edited_by_id
      t.text :edit_rationale
      t.timestamps
    end

    create_table :planned_initiatives do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :management_discovery_context, null: false, foreign_key: true
      t.string :initiative_type, null: false
      t.text :description, null: false
      t.string :timing
      t.string :status, null: false
      t.string :affected_areas, array: true, null: false, default: []
      t.string :evidence, array: true, null: false, default: []
      t.timestamps
    end
  end
end
