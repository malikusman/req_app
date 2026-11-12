# frozen_string_literal: true

class ProcessClusterPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      consultant? ? scope.where(company_id: assigned_company_ids) : scope.none
    end
  end
end
