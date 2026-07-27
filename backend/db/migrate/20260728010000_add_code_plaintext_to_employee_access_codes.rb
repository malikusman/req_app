# frozen_string_literal: true

class AddCodePlaintextToEmployeeAccessCodes < ActiveRecord::Migration[7.1]
  def change
    add_column :employee_access_codes, :code_plaintext, :string
  end
end
