# frozen_string_literal: true

class ConsultantChatMessagePolicy < ApplicationPolicy
  def index?
    (consultant? || platform?) && co_consultants_present?
  end

  def create?
    consultant? && assigned_company?(record.company_id) && co_consultants_present?
  end

  private

  def co_consultants_present?
    company_id = record.is_a?(ConsultantChatMessage) ? record.company_id : record
    ConsultantAssignment.active.where(company_id: company_id).count >= 2
  end
end
