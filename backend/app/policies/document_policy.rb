# frozen_string_literal: true

class DocumentPolicy < ApplicationPolicy
  def index?
    company? || reviewer? || platform?
  end

  def show?
    company_can_access? || platform? || reviewer_assigned?
  end

  def download?
    show? && record.status == "ready"
  end

  def create?
    company_admin?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(company_id: company_id)
      elsif reviewer?
        scope.where(company_id: assigned_company_ids, source: "company_portal_upload")
      else
        scope.none
      end
    end
  end

  private

  def company_can_access?
    company? && record.company_id == company_id
  end

  def reviewer_assigned?
    reviewer? && assigned_company?(record.company_id)
  end
end
