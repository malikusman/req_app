# frozen_string_literal: true

# A finding is one piece of work, in one role, that costs the company something —
# the unit the Diagnostic Report is built from ("role by role, task by task").
#
# Until now the interview's per-area answers (how the work happens, what snags, how
# often, how long) were flattened into company-level keyword signals, and the time
# answers were thrown away. This keeps them, per role, with hours computed in code.
class CreateFindingsAndBenchmarkRates < ActiveRecord::Migration[7.1]
  def change
    create_table :findings do |t|
      t.references :company, null: false, foreign_key: true
      t.references :employee, foreign_key: true
      t.references :conversation, foreign_key: true
      # Stable identity for re-building from the same interview: one finding per
      # conversation per role area. Consultant edits survive a rebuild.
      t.string :source_key, null: false

      t.string :department
      t.string :role_title
      t.string :area, null: false
      t.string :title
      t.text :what_happens_now
      t.text :friction

      # Recorded, never calculated by a model: the employee's words and numbers.
      t.string :frequency_as_said
      t.decimal :frequency_min, precision: 10, scale: 2
      t.decimal :frequency_max, precision: 10, scale: 2
      t.string :frequency_unit
      t.string :duration_as_said
      t.decimal :duration_min, precision: 10, scale: 2
      t.decimal :duration_max, precision: 10, scale: 2
      t.string :duration_unit
      t.string :effort_type, null: false, default: "unknown"

      # Computed in Ruby from the fields above, with the assumptions in hours_basis.
      t.integer :annual_hours_min
      t.integer :annual_hours_max
      t.jsonb :hours_basis, null: false, default: {}

      # discovery (an employee interview) | discovery_partial (an interview that did
      # not finish) | deep_dive | consultant
      t.string :basis, null: false, default: "discovery"
      t.string :confidence, null: false, default: "medium"
      # The only person in the company with this role: every finding about the role
      # identifies them, so a consultant must review it before a client sees it.
      t.boolean :single_occupant_role, null: false, default: false

      # draft -> approved | hidden | merged. Set by consultant review.
      t.string :status, null: false, default: "draft"
      t.references :merged_into, foreign_key: { to_table: :findings }
      t.jsonb :evidence, null: false, default: {}

      t.timestamps
    end
    add_index :findings, %i[company_id source_key], unique: true
    add_index :findings, %i[company_id status]

    # What an hour of a client role's time is worth, for "indicatively worth AED X".
    # Benchmark loaded cost by role family and market — never client salary data —
    # and the version used is printed in the report. Deliberately empty: the values
    # are Mjadi's to supply. Until a rate exists, reports show hours only.
    create_table :benchmark_rates do |t|
      t.string :version, null: false
      t.string :market, null: false, default: "AE"
      t.string :role_family, null: false
      t.string :currency, null: false, default: "AED"
      t.decimal :hourly_rate_min, precision: 10, scale: 2, null: false
      t.decimal :hourly_rate_max, precision: 10, scale: 2, null: false
      t.text :source
      t.date :effective_from, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :benchmark_rates, %i[version market role_family], unique: true
  end
end
