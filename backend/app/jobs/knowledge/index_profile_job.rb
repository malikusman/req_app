# frozen_string_literal: true

module Knowledge
  class IndexProfileJob < ApplicationJob
    queue_as :default

    def perform(company_id)
      company = Company.find_by(id: company_id)
      return unless company

      Knowledge::IndexProfileService.call(company: company)
    end
  end
end
