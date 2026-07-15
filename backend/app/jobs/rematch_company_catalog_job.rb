# frozen_string_literal: true

class RematchCompanyCatalogJob < ApplicationJob
  queue_as :default

  def perform(company_id = nil)
    scope = company_id.present? ? Company.where(id: company_id) : Company.all
    scope.find_each do |company|
      Catalog::CompanyFitService.call(company: company)
    rescue StandardError => e
      Rails.logger.error("[RematchCompanyCatalogJob] company=#{company.id} failed: #{e.message}")
    end
  end
end
