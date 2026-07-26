# frozen_string_literal: true

class AddIntelligenceUpdatedAtToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :intelligence_updated_at, :datetime
  end
end
