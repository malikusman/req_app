# frozen_string_literal: true

class AllowNullEmployeePhone < ActiveRecord::Migration[7.1]
  def change
    change_column_null :employees, :phone_e164, true
  end
end
