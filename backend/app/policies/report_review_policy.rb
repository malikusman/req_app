# frozen_string_literal: true

class ReportReviewPolicy < ApplicationPolicy
  def show?
    platform? || owns_review? || co_consultant_on_report?
  end

  def update?
    consultant? && owns_review? && !record.submitted?
  end

  def submit?
    update?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif consultant?
        scope.where(consultant_user_id: context.actor.id)
          .or(scope.where(company_id: context.actor.active_company_ids))
      else
        scope.none
      end
    end
  end

  private

  def owns_review?
    consultant? && record.consultant_user_id == context.actor.id
  end

  def co_consultant_on_report?
    consultant? &&
      assigned_company?(record.company_id) &&
      record.report.report_reviews.exists?(consultant_user_id: context.actor.id) == false &&
      record.report.report_reviews.exists?
  end
end
