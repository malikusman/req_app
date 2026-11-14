# frozen_string_literal: true

class AddProfileProvenanceAndLegacyProfileToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :profile_provenance, :jsonb, null: false, default: {}
    add_column :companies, :legacy_profile, :jsonb, null: false, default: {}
  end
end
