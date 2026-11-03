# frozen_string_literal: true

# The key user's role in their company (Doc 07 §3, S5) — "Operations Manager" —
# distinct from their portal role.
class AddJobTitleToCompanyUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :company_users, :job_title, :string
  end
end
