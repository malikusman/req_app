# frozen_string_literal: true

# The engagement Mjadi sets up for a client (Doc 06 §3.4, Doc 07 §3) and the
# people planned to take part in it (Doc 07 §7). Planned people are not
# employees yet: they may have no phone, and counting them as invited would
# distort participation.
class CreateEngagementsAndParticipants < ActiveRecord::Migration[7.1]
  def change
    create_table :engagements do |t|
      t.references :company, null: false, foreign_key: true
      t.string :status, null: false, default: "SET_UP"
      t.jsonb :status_history, null: false, default: []
      t.string :scope_type, null: false, default: "COMPANY"
      t.text :departments_in_scope, array: true, null: false, default: []
      t.references :key_user, foreign_key: { to_table: :company_users }
      t.references :lead_consultant, foreign_key: { to_table: :consultant_users }
      t.text :languages, array: true, null: false, default: ["en"]
      t.string :proposal_reference
      t.datetime :confidentiality_acknowledged_at
      t.references :confidentiality_acknowledged_by, foreign_key: { to_table: :company_users }
      t.datetime :onboarding_submitted_at
      t.jsonb :planned_departments, null: false, default: []
      t.timestamps
    end
    add_index :engagements, %i[company_id status]

    create_table :engagement_participants do |t|
      t.references :engagement, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.string :participant_type, null: false
      t.string :name, null: false
      t.string :role_title
      t.string :department
      t.string :scope
      t.string :email
      t.string :phone_e164
      t.string :preferred_language
      t.boolean :nominated_by_client, null: false, default: true
      t.boolean :added_after_pricing, null: false, default: false
      t.string :source, null: false, default: "ONBOARDING"
      t.references :employee, foreign_key: true
      t.timestamps
    end
    add_index :engagement_participants, %i[engagement_id participant_type]
    add_index :engagement_participants, %i[engagement_id phone_e164], unique: true,
                                                                       where: "phone_e164 IS NOT NULL"
  end
end
