# frozen_string_literal: true

# Rate card version 1 (placeholder values, Decision Register K2) and the 60%
# margin floor (B12), so an engagement can be priced as soon as it reaches
# Stage 1 pricing.
class SeedFirstRateCardAndMarginFloor < ActiveRecord::Migration[7.1]
  def up
    RateCardVersion.reset_column_information
    MarginFloorVersion.reset_column_information
    Pricing::Defaults.ensure!
  end

  def down
    # Versions are history; nothing to undo.
  end
end
