# frozen_string_literal: true

class ReviewerAssignmentPolicy < ApplicationPolicy
  def index?
    platform? || reviewer?
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
      elsif reviewer?
        scope.active.where(reviewer_user_id: context.actor.id)
      else
        scope.none
      end
    end
  end
end
