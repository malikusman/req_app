# frozen_string_literal: true

class ReviewerUserPolicy < ApplicationPolicy
  def index?
    platform?
  end

  def show?
    platform? || (reviewer? && record.id == context.actor.id)
  end

  def create?
    platform?
  end

  def update?
    platform? || (reviewer? && record.id == context.actor.id)
  end
end
