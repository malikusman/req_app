# frozen_string_literal: true

# A consultant's wording is an overlay on the machine's, never a replacement: the
# interview-derived fields stay as captured (and are refreshed by a rebuild), and
# what the consultant wrote survives every rebuild.
class AddConsultantReviewToFindings < ActiveRecord::Migration[7.1]
  def change
    change_table :findings, bulk: true do |t|
      t.string :consultant_title
      t.text :consultant_what_happens_now
      t.text :consultant_friction
      t.text :consultant_note
      t.references :reviewed_by, foreign_key: { to_table: :consultant_users }
      t.datetime :reviewed_at
    end
  end
end
