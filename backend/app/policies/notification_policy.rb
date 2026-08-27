# frozen_string_literal: true

class NotificationPolicy < ApplicationPolicy
  def index?
    company? || consultant? || platform?
  end

  def update?
    record.recipient == context.actor
  end

  def mark_all_read?
    index?
  end

  class Scope < Scope
    def resolve
      scope.where(recipient: context.actor)
    end
  end
end
