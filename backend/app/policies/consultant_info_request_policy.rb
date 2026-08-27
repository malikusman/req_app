# frozen_string_literal: true

class ConsultantInfoRequestPolicy < ApplicationPolicy
  def index?
    consultant? && assigned_company?(record.is_a?(Class) ? nil : record.company_id)
  end

  def show?
    consultant? && assigned_company?(record.company_id)
  end

  def create?
    consultant? && assigned_company?(record.company_id)
  end

  class Scope < Scope
    def resolve
      if consultant?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
