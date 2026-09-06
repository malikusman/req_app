# frozen_string_literal: true

class ConsultantOutreachPolicy < ApplicationPolicy
  def index?
    consultant? || company?
  end

  def show?
    return true if consultant? && assigned_company?(record.company_id)
    return true if company? && record.company_id == company_id

    false
  end

  def create?
    consultant? && assigned_company?(record.company_id)
  end

  def approve?
    company_admin? && record.company_id == company_id
  end

  def decline?
    approve?
  end

  def answer?
    company_admin? && record.company_id == company_id
  end

  class Scope < Scope
    def resolve
      if consultant?
        scope.where(company_id: assigned_company_ids)
      elsif company?
        scope.where(company_id: company_id)
      else
        scope.none
      end
    end
  end
end
