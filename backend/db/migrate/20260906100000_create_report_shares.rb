# frozen_string_literal: true

# "Send the board the brief, not the evidence" is a genuinely different act from
# sharing the whole deliverable, so a share link is scoped to one rendering.
#
# reports.share_token stays where it is and keeps resolving: links already handed
# to clients must not break. New links get a row here.
class CreateReportShares < ActiveRecord::Migration[7.1]
  def change
    create_table :report_shares do |t|
      t.references :report, null: false, foreign_key: true
      t.string :variant, null: false
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :report_shares, :token, unique: true
    add_index :report_shares, %i[report_id variant]

    # So an access record can say WHICH rendering was opened.
    add_column :report_share_accesses, :variant, :string
  end
end
