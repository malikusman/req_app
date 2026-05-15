# frozen_string_literal: true

class AggregateIntelligenceJob < ApplicationJob
  queue_as :default

  def perform(company_id, department = nil)
    company = Company.find_by(id: company_id)
    return unless company

    Intelligence::AggregateCompanyIntelligence.call(company: company, department: department)
  end
end
