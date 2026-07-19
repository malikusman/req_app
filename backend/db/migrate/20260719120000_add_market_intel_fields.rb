# frozen_string_literal: true

class AddMarketIntelFields < ActiveRecord::Migration[7.1]
  def change
    add_column :catalog_candidates, :analysis_status, :string, null: false, default: "pending"
    add_column :catalog_candidates, :analyzed_at, :datetime
    add_column :catalog_candidates, :published_at, :datetime
    add_column :catalog_candidates, :industries, :jsonb, null: false, default: []
    add_column :catalog_candidates, :topics, :jsonb, null: false, default: []
    add_column :catalog_candidates, :summary, :text

    add_index :catalog_candidates, :analysis_status
    add_index :catalog_candidates, :entity_type
    add_index :catalog_candidates, :published_at

    create_table :employee_market_alerts do |t|
      t.references :employee, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :catalog_candidate, null: false, foreign_key: true
      t.float :fit_score, null: false, default: 0.0
      t.text :fit_rationale
      t.jsonb :email_body, null: false, default: {}
      t.string :status, null: false, default: "draft"
      t.string :period_month, null: false
      t.datetime :sent_at
      t.string :delivery_status
      t.timestamps
    end

    add_index :employee_market_alerts, %i[employee_id catalog_candidate_id],
              unique: true, name: "idx_employee_market_alerts_unique_candidate"
    add_index :employee_market_alerts, %i[employee_id period_month]
    add_index :employee_market_alerts, :status
  end
end
