# frozen_string_literal: true

class CompanyProfileContext < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :profile_context, :jsonb, default: {}, null: false
    add_column :companies, :profile_context_version, :integer, default: 1, null: false
  end
end
