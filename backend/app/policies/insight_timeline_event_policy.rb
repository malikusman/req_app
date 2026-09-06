# frozen_string_literal: true

class InsightTimelineEventPolicy < ApplicationPolicy
  def index?
    platform? || company? || consultant?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(company_id: company_id)
      elsif consultant?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
