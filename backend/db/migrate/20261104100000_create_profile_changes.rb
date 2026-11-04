# frozen_string_literal: true

# A record of each change to a company's facts once onboarding has been
# submitted (Doc 07 §12: edits after submission are made by the key user, or by
# a consultant with an audit record). Written by Companies::ProfileUpdater.
class CreateProfileChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :profile_changes do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.string :field, null: false
      t.jsonb :from_value
      t.jsonb :to_value
      t.string :source, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.timestamps
    end
    add_index :profile_changes, %i[company_id created_at]
  end
end
