# frozen_string_literal: true

class BillingPolicy < ApplicationPolicy
  def show?
    company?
  end

  def checkout?
    company_admin?
  end
end
