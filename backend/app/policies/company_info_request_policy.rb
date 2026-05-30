# frozen_string_literal: true

class CompanyInfoRequestPolicy < ApplicationPolicy
  def index?
    company_admin? || reviewer? || platform?
  end

  def show?
    (company_admin? && same_company?(record)) ||
      (reviewer? && assigned_company?(record.company_id)) ||
      platform?
  end

  def create?
    target_company_id = record.is_a?(Company) ? record.id : record.company_id
    (reviewer? && assigned_company?(target_company_id)) || platform?
  end

  def reply?
    company_admin? && same_company?(record)
  end

  def close?
    (reviewer? && assigned_company?(record.company_id)) || platform?
  end

  class Scope < Scope
    def resolve
      if company?
        scope.where(company_id: company_id)
      elsif reviewer?
        scope.where(company_id: assigned_company_ids)
      elsif platform?
        scope.all
      else
        scope.none
      end
    end
  end
end
