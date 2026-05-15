# frozen_string_literal: true

class EmployeeInvitation < ApplicationRecord
  belongs_to :company
  belongs_to :employee
  belongs_to :company_user, optional: true

  DELIVERY_STATUSES = %w[queued sent delivered failed].freeze

  validates :delivery_status, inclusion: { in: DELIVERY_STATUSES }
end
