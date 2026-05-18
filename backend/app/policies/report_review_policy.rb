# frozen_string_literal: true

class ReportReviewPolicy < ApplicationPolicy
  def show?
    platform? || owns_review? || co_reviewer_on_report?
  end

  def update?
    reviewer? && owns_review? && !record.submitted?
  end

  def submit?
    update?
  end

  class Scope < Scope
    def resolve
      if platform?
        scope.all
      elsif reviewer?
        scope.where(reviewer_user_id: context.actor.id)
          .or(scope.where(company_id: context.actor.active_company_ids))
      else
        scope.none
      end
    end
  end

  private

  def owns_review?
    reviewer? && record.reviewer_user_id == context.actor.id
  end

  def co_reviewer_on_report?
    reviewer? &&
      assigned_company?(record.company_id) &&
      record.report.report_reviews.exists?(reviewer_user_id: context.actor.id) == false &&
      record.report.report_reviews.exists?
  end
end
