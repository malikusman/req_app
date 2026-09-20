# frozen_string_literal: true

# PatternUpsertService used to take `[stored, fresh].max`, so a pattern that
# peaked once stayed at that confidence forever even as its evidence weakened.
# It now takes the fresh value — which means the peak would be lost unless it is
# recorded. company_signals already keeps strength_history for the same reason;
# this mirrors it.
class AddConfidenceHistoryToPatterns < ActiveRecord::Migration[7.1]
  def change
    add_column :patterns, :confidence_history, :jsonb, default: [], null: false
  end
end
