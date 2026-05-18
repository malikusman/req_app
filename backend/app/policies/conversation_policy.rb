# frozen_string_literal: true

class ConversationPolicy < ApplicationPolicy
  def index?
    platform? || reviewer?
  end

  def show?
    platform? || assigned_company?(record.company_id)
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif reviewer?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
