# frozen_string_literal: true

class AddWebsiteUrlToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :website_url, :string
  end
end
