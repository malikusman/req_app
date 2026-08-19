# frozen_string_literal: true

class AddQuestionnaireVersionToCompanies < ActiveRecord::Migration[7.1]
  def change
    # Version marker for the onboarding questionnaire rebuild. Existing records
    # stay at the default (1) and keep v1 behaviour; new-onboarding sessions are
    # stamped 2 by a later stage.
    add_column :companies, :questionnaire_version, :integer, null: false, default: 1
  end
end