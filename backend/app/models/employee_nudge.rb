# frozen_string_literal: true

class EmployeeNudge < ApplicationRecord
  belongs_to :employee
  belongs_to :company_user, optional: true
  belongs_to :conversation, optional: true
end
