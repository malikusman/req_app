# frozen_string_literal: true

class ReportReviewComment < ApplicationRecord
  belongs_to :report_review
  belongs_to :consultant_user

  validates :section_key, presence: true
  validates :body, presence: true
end
