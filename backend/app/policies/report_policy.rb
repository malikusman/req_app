# frozen_string_literal: true

class ReportPolicy < ApplicationPolicy
  def index?
    platform? || company? || consultant?
  end

  def show?
    return true if platform?
    return same_company?(record) if company?
    return assigned_company?(record.company_id) && record.status == "ready" if consultant?

    false
  end

  # Generation belongs to the consultant, with the platform as the fallback.
  #
  # The consultant is the one who knows whether new evidence changes the advice,
  # so the trigger sits with them rather than with the client. The platform needs
  # it too: a company with no consultant assigned yet has nobody who could
  # generate for it, and would otherwise never get a first report.
  #
  # The company is deliberately excluded — a client does not commission their own
  # deliverable, and nothing reaches them without review and approval either way.
  # Scoping to a company the consultant is actually assigned to is the
  # controller's job, via policy_scope(Company), as it is for every other
  # consultant action.
  def create?
    platform? || consultant?
  end

  def download?
    return true if platform?
    return same_company?(record) && record.status == "ready" && record.visibility == "shared_with_company" if company?
    return assigned_company?(record.company_id) && record.status == "ready" if consultant?

    false
  end

  def share?
    company? && company_admin? && record.visibility == "shared_with_company"
  end

  def approve?
    platform?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif company?
        scope.where(company_id: company_id)
      elsif consultant?
        scope.where(company_id: assigned_company_ids, status: "ready")
      else
        scope.none
      end
    end
  end
end
