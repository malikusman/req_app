# frozen_string_literal: true

class DiscoveryPackagePolicy < ApplicationPolicy
  def show?
    consultant? && assigned_company?(record.company_id)
  end

  # Amending the package is the consultant's core act of judgement, so it is gated
  # on assignment exactly like reading it.
  def update?
    show?
  end

  class Scope < Scope
    def resolve
      if consultant?
        scope.where(company_id: assigned_company_ids)
      else
        scope.none
      end
    end
  end
end
