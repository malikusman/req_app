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

  # Nobody generates a report over HTTP. The company portal is view/download of
  # shared reports only, so that nothing reaches a client without expert review.
  #
  # Kept explicit rather than deleted: a company-facing POST /company/reports
  # existed for a long time behind this `false`, which meant the portal shipped a
  # "Generate refreshed report" button that could only ever return Forbidden.
  # Leaving the rule here states the intent to whoever considers adding it back.
  #
  # Generation today: Reports::GenerateReportService (rake, seeders), and
  # Reports::ConsultantRefreshService for a consultant re-cutting a stale report.
  def create?
    false
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
