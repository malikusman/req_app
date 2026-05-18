# frozen_string_literal: true

class DocumentPolicy < ApplicationPolicy
  def index?
    company?
  end

  def create?
    company_admin?
  end

  class Scope < Scope
    def resolve
      company? ? scope.where(company_id: company_id) : scope.none
    end
  end
end
