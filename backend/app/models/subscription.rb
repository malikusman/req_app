# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :company

  PLANS = %w[trial starter growth enterprise].freeze
  STATUSES = %w[trial active suspended churned].freeze

  validates :plan, inclusion: { in: PLANS }
  validates :status, inclusion: { in: STATUSES }

  after_create :apply_plan_defaults

  def active_for_access?
    return false if status == "churned" || status == "suspended"
    return trial_ends_at.future? if status == "trial" && trial_ends_at.present?

    %w[trial active].include?(status)
  end

  private

  def apply_plan_defaults
    Subscriptions::PlanLimits.apply_defaults!(self)
  end
end
