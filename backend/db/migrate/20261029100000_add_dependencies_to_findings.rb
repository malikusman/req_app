# frozen_string_literal: true

# What must be true before a finding's change can work (Doc 15 §4.5.2), in two
# forms: a sentence about a condition in the business — "supplier codes in the
# ERP are consistent" — and links to other findings that must be addressed first.
#
# Both are drafted by a model and decided by the consultant, as cause and
# direction are. depends_on_ids is the draft; consultant_depends_on_ids is the
# consultant's own list, nil while they follow the draft and [] when they removed
# every link.
class AddDependenciesToFindings < ActiveRecord::Migration[7.1]
  def change
    change_table :findings, bulk: true do |t|
      t.text :dependency
      t.text :consultant_dependency
      t.bigint :depends_on_ids, array: true, default: [], null: false
      t.bigint :consultant_depends_on_ids, array: true
    end
  end
end
