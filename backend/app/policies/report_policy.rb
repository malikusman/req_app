# frozen_string_literal: true

class ReportPolicy < ApplicationPolicy
  def index?
    platform? || company? || reviewer?
  end

  def show?
    return true if platform?
    return same_company?(record) if company?
    return assigned_company?(record.company_id) && record.status == "ready" if reviewer?

    false
  end

  def create?
    company? && company_admin?
  end

  def download?
    show? && (company? || platform?)
  end

  def share?
    create?
  end

  def approve?
    platform?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(company_id: company_id)
      elsif reviewer?
        scope.where(company_id: assigned_company_ids, status: "ready")
      else
        scope.none
      end
    end
  end
end
