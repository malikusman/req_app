# frozen_string_literal: true

class SettingsPolicy < ApplicationPolicy
  def organization?
    company_admin?
  end

  def update_organization?
    company_admin?
  end

  def security?
    company_admin?
  end
end
