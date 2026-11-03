# frozen_string_literal: true

# The Doc 07 onboarding form replaces the 43-question questionnaire.
# - The key user's own language (A4) and which acknowledgement text they agreed to (A5).
# - Old questionnaire answers move to legacy_profile, where consultants can still
#   read them; questionnaire_answers now holds the new form's answers.
class PrepareOnboardingForm < ActiveRecord::Migration[7.1]
  def up
    add_column :company_users, :preferred_language, :string
    add_column :engagements, :confidentiality_text_version, :string

    execute <<~SQL.squish
      UPDATE companies
      SET legacy_profile = legacy_profile || jsonb_build_object('questionnaire_v1', questionnaire_answers),
          questionnaire_answers = '{}'::jsonb,
          questionnaire_step = NULL
      WHERE questionnaire_answers <> '{}'::jsonb
        AND NOT legacy_profile ? 'questionnaire_v1'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE companies
      SET questionnaire_answers = legacy_profile -> 'questionnaire_v1',
          legacy_profile = legacy_profile - 'questionnaire_v1'
      WHERE legacy_profile ? 'questionnaire_v1'
    SQL
    remove_column :engagements, :confidentiality_text_version
    remove_column :company_users, :preferred_language
  end
end
