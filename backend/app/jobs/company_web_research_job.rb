# frozen_string_literal: true

class CompanyWebResearchJob < ApplicationJob
  queue_as :default

  def perform(company_id, force: false)
    company = Company.find_by(id: company_id)
    return if company.blank? || company.website_url.blank?

    Companies::WebResearchService.call(company: company, force: force)
  end
end
