# frozen_string_literal: true

class ReportReviewFindingPolicy < ApplicationPolicy
  def index?
    show_parent_review?
  end

  def create?
    consultant? && owns_review? && !record.report_review.submitted?
  end

  def update?
    consultant? && record.consultant_user_id == context.actor.id && !record.report_review.submitted?
  end

  def destroy?
    update?
  end

  private

  def show_parent_review?
    review = record.is_a?(ReportReviewFinding) ? record.report_review : record
    ReportReviewPolicy.new(context, review).show?
  end

  def owns_review?
    consultant? && record.report_review.consultant_user_id == context.actor.id
  end
end
