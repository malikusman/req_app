# frozen_string_literal: true

class OneActiveAnalysisRunPerCompany < ActiveRecord::Migration[7.1]
  def change
    add_index :document_analysis_runs, :company_id,
              unique: true,
              where: "status IN ('queued', 'running')",
              name: "index_document_analysis_runs_one_active_per_company"
  end
end
