# frozen_string_literal: true

class CompanyInfoRequestReply < ApplicationRecord
  belongs_to :company_info_request
  belongs_to :sender, polymorphic: true
  belongs_to :document, optional: true

  validates :body, presence: true
end
