# frozen_string_literal: true

class ReviewDiscussionPolicy < ApplicationPolicy
  def index?
    consultant_on_report?
  end

  def create?
    consultant_on_report?
  end

  def reply?
    consultant_on_report?
  end

  def resolve?
    consultant_on_report? && record.author_consultant_user_id == context.actor.id
  end

  class Scope < Scope
    def resolve
      if consultant?
        scope.where(company_id: context.actor.active_company_ids)
      else
        scope.none
      end
    end
  end

  private

  def consultant_on_report?
    return false unless consultant?

    company_id = record.company_id
    return false unless assigned_company?(company_id)

    record.report.report_reviews.exists?(consultant_user_id: context.actor.id)
  end
end
