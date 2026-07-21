# frozen_string_literal: true

class EmployeeMarketAlert < ApplicationRecord
  belongs_to :employee
  belongs_to :company
  belongs_to :catalog_candidate

  STATUSES = %w[draft sent suppressed failed].freeze

  validates :fit_score, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :period_month, presence: true
  validates :catalog_candidate_id, uniqueness: { scope: :employee_id }

  scope :sent, -> { where(status: "sent") }
  scope :for_month, ->(ym) { where(period_month: ym) }

  def self.period_month_for(time = Time.current)
    time.utc.strftime("%Y-%m")
  end

  def self.sent_count_this_month(employee_id, time = Time.current)
    sent.where(employee_id: employee_id, period_month: period_month_for(time)).count
  end
end
