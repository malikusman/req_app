# frozen_string_literal: true

class RecommendationPolicy < ApplicationPolicy
  def index?
    platform? || company? || reviewer?
  end

  def update_feedback?
    company? && company_admin?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(company_id: company_id)
      elsif reviewer?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
