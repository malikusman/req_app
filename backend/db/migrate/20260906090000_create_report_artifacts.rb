# frozen_string_literal: true

# One reviewed Report can ship as several renderings — a short executive brief for
# the owner who decides, the full report for the team that acts. They are
# PROJECTIONS of one snapshot, never separate analyses: if a number differs
# between two artifacts that is a bug with a single cause, not a reconciliation
# problem.
#
# A table rather than exec_* columns on `reports` so a third variant needs no
# migration.
class CreateReportArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :report_artifacts do |t|
      t.references :report, null: false, foreign_key: true
      t.string :variant, null: false
      t.string :storage_key
      t.string :content_type, default: "application/pdf"
      t.integer :page_count
      t.datetime :generated_at
      t.text :error_message
      t.timestamps
    end

    add_index :report_artifacts, %i[report_id variant], unique: true
  end
end
