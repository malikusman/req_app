# frozen_string_literal: true

class AddCompanyJoinCode < ActiveRecord::Migration[7.1]
  def up
    add_column :companies, :join_code, :string, limit: 5
    add_index :companies, :join_code, unique: true

    Company.reset_column_information
    Company.find_each do |company|
      company.update_column(:join_code, generate_join_code)
    end

    change_column_null :companies, :join_code, false
  end

  def down
    remove_index :companies, :join_code
    remove_column :companies, :join_code
  end

  private

  def generate_join_code
    loop do
      code = SecureRandom.alphanumeric(5).upcase
      break code unless Company.exists?(join_code: code)
    end
  end
end
