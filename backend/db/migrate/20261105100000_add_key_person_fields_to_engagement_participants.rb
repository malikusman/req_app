# frozen_string_literal: true

# What a key person needs once the conversations with leadership begin (Doc 06
# §3.6, Doc 08, Doc 14 §4–5, §9): who they are to the conversation (persona), how
# far they have got, how they get in (a signed link for managers; the key user
# signs in to the portal), their consent, and the reminders sent to them.
class AddKeyPersonFieldsToEngagementParticipants < ActiveRecord::Migration[7.1]
  def change
    change_table :engagement_participants, bulk: true do |t|
      t.string :persona
      t.string :participation_status, null: false, default: "NOT_INVITED"
      t.references :company_user, foreign_key: true, index: true
      t.datetime :invited_at
      t.string :access_token_digest
      t.datetime :access_token_expires_at
      t.datetime :consent_recorded_at
      t.string :consent_text_version
      t.integer :reminder_count, null: false, default: 0
      t.datetime :last_reminded_at
      t.text :consultant_focus
    end
    add_index :engagement_participants, :access_token_digest, unique: true
  end
end
