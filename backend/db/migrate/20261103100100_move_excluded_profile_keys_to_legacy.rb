# frozen_string_literal: true

# Goals and revenue band out of company_profile, sizes onto the one vocabulary,
# provenance recorded, questionnaire-informed analysis retired. See
# Companies::LegacyProfileMigration. Not reversed: the moved values stay in
# legacy_profile, so nothing is lost.
class MoveExcludedProfileKeysToLegacy < ActiveRecord::Migration[7.1]
  def up
    Company.reset_column_information
    Company.find_each { |company| Companies::LegacyProfileMigration.call(company) }
  end

  def down; end
end
