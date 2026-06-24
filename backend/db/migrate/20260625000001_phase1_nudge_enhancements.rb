# frozen_string_literal: true

class Phase1NudgeEnhancements < ActiveRecord::Migration[7.1]
  def change
    add_column :employees, :email, :string
    add_index :employees, :email, where: "email IS NOT NULL"

    add_column :employee_nudges, :delivery_status, :string, default: "queued", null: false
    add_column :employee_nudges, :error_message, :text
    add_column :employee_nudges, :whatsapp_status, :string
    add_column :employee_nudges, :email_status, :string
  end
end
