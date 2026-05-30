# frozen_string_literal: true

class ReviewerChatMessagePolicy < ApplicationPolicy
  def index?
    (reviewer? || platform?) && co_reviewers_present?
  end

  def create?
    ((reviewer? && assigned_company?(record.company_id)) || platform?) && co_reviewers_present?
  end

  private

  def co_reviewers_present?
    company_id = record.is_a?(ReviewerChatMessage) ? record.company_id : record
    ReviewerAssignment.active.where(company_id: company_id).count >= 2
  end
end
