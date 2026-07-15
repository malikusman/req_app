# frozen_string_literal: true

class DocumentPolicy < ApplicationPolicy
  def index?
    company? || reviewer?
  end

  def show?
    return true if company? && record.company_id == company_id
    return true if reviewer? && assigned_company?(record.company_id) && record.try(:reviewer_visible) != false

    false
  end

  def create?
    company_admin?
  end

  def update?
    company_admin?
  end

  def download?
    show?
  end

  def destroy?
    company_admin?
  end

  class Scope < Scope
    def resolve
      if company?
        scope.where(company_id: company_id)
      elsif reviewer?
        scope.where(company_id: assigned_company_ids).where("reviewer_visible IS DISTINCT FROM FALSE")
      else
        scope.none
      end
    end
  end
end
