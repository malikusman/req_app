# frozen_string_literal: true

class AddCompanyProfileToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :company_profile, :jsonb, null: false, default: {}
  end
end
