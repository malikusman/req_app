# frozen_string_literal: true

# Why each piece of work costs what it does, and the kind of change that would
# address it (Doc 15 §4.5.2): drafted from the finding by a model, checked and
# reworded by the consultant. The direction names the kind of change and what it
# does — never how it is built, which is Stage 2.
#
# cause_stated says whether the employee gave the cause themselves; when they did
# not, the report labels it as analysis (Doc 15 §8.2). draft_digest records what
# the draft was written from, so a reworded finding is redrafted and an unchanged
# one is not.
class AddCauseAndDirectionToFindings < ActiveRecord::Migration[7.1]
  def change
    change_table :findings, bulk: true do |t|
      t.text :cause
      t.boolean :cause_stated, default: false, null: false
      t.string :intervention_type
      t.text :direction
      t.string :draft_digest
      t.text :consultant_cause
      t.boolean :consultant_cause_stated
      t.string :consultant_intervention_type
      t.text :consultant_direction
    end
  end
end
