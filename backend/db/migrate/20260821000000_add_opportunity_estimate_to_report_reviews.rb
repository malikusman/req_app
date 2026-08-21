# frozen_string_literal: true

# Reviewer-estimated opportunity value for the report — the CEO-facing headline
# ("how much is this worth"), entered by the expert who stands behind it.
class AddOpportunityEstimateToReportReviews < ActiveRecord::Migration[7.1]
  def change
    add_column :report_reviews, :opportunity_amount, :bigint
    add_column :report_reviews, :opportunity_unit, :string
    add_column :report_reviews, :opportunity_basis, :text
  end
end
