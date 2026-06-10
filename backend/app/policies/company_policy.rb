# frozen_string_literal: true

class CompanyPolicy < ApplicationPolicy
  def index?
    platform?
  end

  def show?
    platform? || own_company?(record) || same_company?(record) || assigned_company?(record.id)
  end

  def create?
    platform?
  end

  def update?
    platform?
  end

  private

  def own_company?(record)
    company? && record.is_a?(::Company) && record.id == company_id
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(id: company_id)
      elsif reviewer?
        scope.where(id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
