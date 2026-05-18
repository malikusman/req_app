# frozen_string_literal: true

class OnboardingPolicy < ApplicationPolicy
  def show?
    company_admin?
  end

  def update_profile?
    company_admin?
  end

  def complete?
    company_admin?
  end
end
