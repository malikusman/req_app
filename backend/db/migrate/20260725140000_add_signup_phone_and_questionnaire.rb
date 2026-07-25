# frozen_string_literal: true

class AddSignupPhoneAndQuestionnaire < ActiveRecord::Migration[7.1]
  def change
    add_column :company_registrations, :admin_phone, :string
    add_column :company_users, :phone, :string

    add_column :companies, :questionnaire_answers, :jsonb, null: false, default: {}
    add_column :companies, :questionnaire_completed_at, :datetime
    add_column :companies, :questionnaire_step, :integer, default: 1, null: false
  end
end
