# frozen_string_literal: true

class RenameCatalogSyncRunErrorsColumn < ActiveRecord::Migration[7.1]
  def change
    rename_column :catalog_sync_runs, :errors, :error_details
  end
end
