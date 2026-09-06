# frozen_string_literal: true

class ConsultantUserPolicy < ApplicationPolicy
  def index?
    platform?
  end

  def show?
    platform? || (consultant? && record.id == context.actor.id)
  end

  def create?
    platform?
  end

  def update?
    platform? || (consultant? && record.id == context.actor.id)
  end

  def expert_index?
    company?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif consultant?
        scope.where(id: context.actor.id)
      else
        scope.none
      end
    end
  end
end
