# frozen_string_literal: true

# A consultant's correction of how often and how long, alongside the interview's
# own figures rather than over them — the same overlay as the wording. Empty means
# "the interview's figures stand". Hours are computed from whichever applies.
class AddConsultantEffortToFindings < ActiveRecord::Migration[7.1]
  def change
    add_column :findings, :consultant_effort, :jsonb, null: false, default: {}
  end
end
