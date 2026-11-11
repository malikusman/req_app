# frozen_string_literal: true

# What consolidation and synthesis produce (Doc 10, Doc 06 §6): which pieces of
# work different people described belong together, what they cost once counted
# once, and what the engagement as a whole shows — root causes, opportunities
# above any one task, and whether leadership's concerns are borne out by what
# staff describe.
#
# Nothing here is overwritten (Doc 06 §1.2). A re-run or a consultant's decision
# makes a new version linked to the one it supersedes; rejected AI output is
# kept, marked rejected. Raw and de-duplicated effort are stored side by side.
#
# All of it is protected synthesis output: it reasons across participants
# (OTHER_EMPLOYEE_PRIVATE) and leadership (MANAGEMENT_STRATEGIC), so consultants
# read it and the client sees only what a consultant approved, inside a released
# report. Employees and their interviews never read any of it.
class CreateSynthesisTables < ActiveRecord::Migration[7.1]
  def change
    create_table :synthesis_runs do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :trigger, null: false
      t.string :status, null: false, default: "QUEUED"
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.string :input_digest
      t.jsonb :coverage, null: false, default: {}
      t.jsonb :prompt_versions, null: false, default: {}
      # P11's run-level output. The consultant's edited picture is kept apart
      # from the model's, and carried into later runs.
      t.jsonb :operating_picture, null: false, default: {}
      t.jsonb :consultant_operating_picture
      t.string :operating_picture_status, null: false, default: "PROPOSED"
      t.jsonb :initiative_conflicts, null: false, default: []
      t.jsonb :role_potential, null: false, default: []
      t.jsonb :coverage_notes, null: false, default: []
      t.string :confidence
      # What the validator removed from a model reply, and why.
      t.jsonb :validation_drops, null: false, default: []
      t.jsonb :counts, null: false, default: {}
      t.string :fallback_reason
      t.text :error
      t.timestamps
    end
    add_index :synthesis_runs, %i[engagement_id version], unique: true

    # P10's verdict on one pair of work items (Doc 10 §8, Doc 06 §6.3).
    create_table :process_relationships do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :synthesis_run, foreign_key: true
      t.references :from_finding, null: false, foreign_key: { to_table: :findings }
      t.references :to_finding, null: false, foreign_key: { to_table: :findings }
      # The two items' wording and figures when judged: a change re-opens the pair.
      t.string :pair_digest, null: false
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false, default: "CURRENT"
      t.string :relationship_type, null: false
      t.string :confidence, null: false
      t.string :recommendation, null: false
      t.string :same_execution, null: false, default: "UNKNOWN"
      t.jsonb :tests, null: false, default: {}
      t.jsonb :variant_assessment, null: false, default: {}
      t.jsonb :evidence_for, null: false, default: []
      t.jsonb :evidence_against, null: false, default: []
      t.text :effort_note
      t.text :rationale
      t.text :clarification
      t.string :origin, null: false, default: "AI"
      t.string :prompt_version
      t.string :schema_version, null: false
      t.timestamps
    end
    add_index :process_relationships, %i[engagement_id pair_digest]
    add_index :process_relationships, %i[engagement_id status]

    create_table :process_clusters do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :synthesis_run, foreign_key: true
      t.string :cluster_key, null: false
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false, default: "PROVISIONAL"
      t.string :name, null: false
      t.text :description
      t.string :cluster_type, null: false
      t.string :departments, array: true, null: false, default: []
      t.string :roles, array: true, null: false, default: []
      t.jsonb :variants, null: false, default: []
      t.jsonb :stages, null: false, default: []
      # One participant: everything said about it describes that person (Doc 10 §22).
      t.boolean :single_member, null: false, default: false
      t.string :fact_status, null: false, default: "INFERRED"
      t.string :confidence
      t.string :origin, null: false, default: "AI"
      t.text :rationale
      t.jsonb :evidence, null: false, default: []
      t.references :decided_by, polymorphic: true
      t.text :decision_rationale
      t.string :schema_version, null: false
      t.timestamps
    end
    add_index :process_clusters, %i[engagement_id cluster_key version], unique: true
    add_index :process_clusters, %i[engagement_id status]

    create_table :process_cluster_members do |t|
      t.references :process_cluster, null: false, foreign_key: true
      t.references :finding, null: false, foreign_key: true
      t.references :employee, foreign_key: true
      t.string :variant_label
      t.integer :stage_order
      # The finding as it stood when clustered; a later rebuild shows as drift.
      t.string :member_digest, null: false
      t.timestamps
    end
    add_index :process_cluster_members, %i[process_cluster_id finding_id], unique: true

    # Raw versus de-duplicated effort for one cluster version (Doc 10 §10.4,
    # Doc 06 §6.4). Every figure here is computed by Synthesis::EffortNormalizer.
    create_table :effort_normalizations do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :process_cluster, null: false, foreign_key: true, index: { unique: true }
      t.decimal :raw_min, precision: 10, scale: 1
      t.decimal :raw_max, precision: 10, scale: 1
      t.decimal :dedup_min, precision: 10, scale: 1
      t.decimal :dedup_max, precision: 10, scale: 1
      t.decimal :waiting_hours_max, precision: 10, scale: 1
      t.jsonb :overlap_adjustments, null: false, default: []
      t.boolean :conservative_adjustment, null: false, default: false
      t.boolean :double_count_warning, null: false, default: false
      t.text :warning_reason
      t.boolean :duplication_flag, null: false, default: false
      t.bigint :participants_counted, array: true, null: false, default: []
      t.string :method_version, null: false
      t.string :confidence
      t.decimal :consultant_min, precision: 10, scale: 1
      t.decimal :consultant_max, precision: 10, scale: 1
      t.text :override_rationale
      t.timestamps
    end

    create_table :root_causes do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :synthesis_run, foreign_key: true
      t.string :root_cause_key, null: false
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false, default: "PROPOSED"
      t.text :statement, null: false
      t.jsonb :explains, null: false, default: []
      t.string :affected_departments, array: true, null: false, default: []
      t.jsonb :supporting_signals, null: false, default: []
      t.string :fact_status, null: false, default: "INFERRED"
      t.string :confidence, null: false
      t.text :what_would_confirm
      t.jsonb :evidence, null: false, default: []
      t.string :origin, null: false, default: "AI"
      t.string :prompt_version
      t.string :schema_version, null: false
      t.timestamps
    end
    add_index :root_causes, %i[engagement_id root_cause_key version], unique: true

    create_table :consultancy_opportunities do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :synthesis_run, foreign_key: true
      t.string :opportunity_key, null: false
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false, default: "PROPOSED"
      t.string :level, null: false
      t.string :category, null: false
      t.string :title, null: false
      t.text :problem_statement, null: false
      t.text :evidence_summary
      t.string :affected_cluster_keys, array: true, null: false, default: []
      t.bigint :affected_finding_ids, array: true, null: false, default: []
      t.string :affected_departments, array: true, null: false, default: []
      t.string :root_cause_key
      # A platform-computed figure, quoted exactly; never one the model made.
      t.text :capacity_reference
      t.string :other_value, array: true, null: false, default: []
      t.text :intervention_direction
      t.string :ai_relevance
      t.text :ai_note
      t.text :management_alignment
      t.text :planned_initiative_conflict
      t.jsonb :dependencies, null: false, default: []
      t.string :recommended_next_action, null: false
      t.text :priority_reason
      # Kept apart on purpose (Doc 10 §15, Doc 08 §17): what leadership said
      # mattered, and what the platform's rule makes of the evidence.
      t.string :management_importance
      t.string :platform_priority
      t.string :platform_priority_rule_version
      t.bigint :strategic_finding_ids, array: true, null: false, default: []
      t.string :confidence, null: false
      t.jsonb :evidence, null: false, default: []
      t.string :origin, null: false, default: "AI"
      t.string :prompt_version
      t.string :schema_version, null: false
      t.timestamps
    end
    add_index :consultancy_opportunities, %i[engagement_id opportunity_key version], unique: true,
                                                                                    name: "idx_opportunities_key_version"
    add_index :consultancy_opportunities, %i[engagement_id status]

    # Whether staff evidence bears out one of leadership's strategic findings
    # (Doc 10 §15, Doc 08 §15 validation_need, §20; P11 management_versus_evidence).
    create_table :management_validations do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.references :synthesis_run, foreign_key: true
      t.references :strategic_finding, null: false, foreign_key: true
      t.integer :strategic_finding_version, null: false
      t.integer :version, null: false, default: 1
      t.bigint :parent_version_id
      t.string :status, null: false, default: "PROPOSED"
      t.text :management_view, null: false
      t.text :what_evidence_shows
      t.string :relationship, null: false
      t.boolean :material, null: false, default: false
      t.text :note
      t.jsonb :evidence, null: false, default: []
      t.text :resolution
      t.string :origin, null: false, default: "AI"
      t.string :prompt_version
      t.string :schema_version, null: false
      t.timestamps
    end
    add_index :management_validations, %i[engagement_id status]

    # Every consultant action on synthesis, with the reason (Doc 10 §17.2,
    # Doc 05 §9.3). Append-only.
    create_table :synthesis_decisions do |t|
      t.references :company, null: false, foreign_key: true
      t.references :engagement, null: false, foreign_key: true
      t.string :action, null: false
      t.references :subject, polymorphic: true, null: false
      t.bigint :before_version_id
      t.bigint :after_version_id
      t.text :rationale, null: false
      t.references :actor, polymorphic: true, null: false
      t.jsonb :details, null: false, default: {}
      t.jsonb :rerun_scope, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
