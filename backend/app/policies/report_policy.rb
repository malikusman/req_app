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
    # Company portal is view/download of shared reports only; generation is reviewer/platform.
    false
  end

  def download?
    return true if platform?
    return same_company?(record) && record.status == "ready" && record.visibility == "shared_with_company" if company?
    return assigned_company?(record.company_id) && record.status == "ready" if reviewer?

    false
  end

  def share?
    company? && company_admin? && record.visibility == "shared_with_company"
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
