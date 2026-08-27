# frozen_string_literal: true

class ConsultantAssignmentPolicy < ApplicationPolicy
  def index?
    platform? || consultant?
  end

  def create?
    platform?
  end

  def destroy?
    platform?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif consultant?
        scope.active.where(consultant_user_id: context.actor.id)
      else
        scope.none
      end
    end
  end
end
