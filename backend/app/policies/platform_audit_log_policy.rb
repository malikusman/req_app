# frozen_string_literal: true

class PlatformAuditLogPolicy < ApplicationPolicy
  def index?
    platform?
  end

  class Scope < Scope
    def resolve
      platform? ? scope.all : scope.none
    end
  end
end
