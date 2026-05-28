# frozen_string_literal: true

class ReviewerInfoRequestPolicy < ApplicationPolicy
  def index?
    reviewer?
  end

  def show?
    reviewer? && assigned_company?(record.company_id)
  end

  def create?
    reviewer? && assigned_company?(record.company_id)
  end

  class Scope < Scope
    def resolve
      if reviewer?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
