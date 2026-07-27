# frozen_string_literal: true

class EmployeePolicy < ApplicationPolicy
  def index?
    platform? || company? || reviewer?
  end

  def show?
    platform? || same_company?(record) || assigned_company?(record.company_id)
  end

  def create?
    company? && company_admin?
  end

  def update?
    company? && company_admin?
  end

  def nudge?
    company_admin?
  end

  def update_phone?
    company_admin?
  end

  def reissue_access_code?
    company_admin?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(company_id: company_id)
      elsif reviewer?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
