# frozen_string_literal: true

class ReviewDiscussionPolicy < ApplicationPolicy
  def index?
    reviewer_on_report?
  end

  def create?
    reviewer_on_report?
  end

  def reply?
    reviewer_on_report?
  end

  def resolve?
    reviewer_on_report? && record.author_reviewer_user_id == context.actor.id
  end

  class Scope < Scope
    def resolve
      if reviewer?
        scope.where(company_id: context.actor.active_company_ids)
      else
        scope.none
      end
    end
  end

  private

  def reviewer_on_report?
    return false unless reviewer?

    company_id = record.company_id
    return false unless assigned_company?(company_id)

    record.report.report_reviews.exists?(reviewer_user_id: context.actor.id)
  end
end
