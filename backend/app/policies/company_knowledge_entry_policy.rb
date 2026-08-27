# frozen_string_literal: true

class CompanyKnowledgeEntryPolicy < ApplicationPolicy
  def index?
    company_admin? || consultant?
  end

  def show?
    return true if company_admin? && record.company_id == company_id
    return true if consultant? && assigned_company?(record.company_id)

    false
  end

  class Scope < Scope
    def resolve
      if company?
        scope.where(company_id: company_id)
      elsif consultant?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
