# frozen_string_literal: true

class EmployeeEmailAndBulkInvite < ActiveRecord::Migration[7.1]
  def change
    change_table :employees, bulk: true do |t|
      t.string :email
    end
    add_index :employees, :email, unique: true, where: "email IS NOT NULL"

    change_table :employee_invitations, bulk: true do |t|
      t.string :email
      t.string :invite_channel, null: false, default: "whatsapp"
    end
    change_column_null :employee_invitations, :phone_e164, true
  end
end
