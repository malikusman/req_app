# frozen_string_literal: true

class ReportRegenerationContext < ActiveRecord::Migration[7.1]
  def change
    change_table :reports, bulk: true do |t|
      t.references :regeneration_source_report, foreign_key: { to_table: :reports }
      t.text :regeneration_note
    end
  end
end
