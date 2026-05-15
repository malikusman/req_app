# frozen_string_literal: true

class Recommendation < ApplicationRecord
  belongs_to :company
  belongs_to :company_feedback_by, class_name: "CompanyUser", optional: true
  has_many :recommendation_feedbacks, dependent: :destroy

  STATUSES = %w[draft published archived].freeze
  FEEDBACKS = %w[no_response interested already_doing not_relevant].freeze
  PRIORITIES = %w[low medium high].freeze

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :company_feedback, inclusion: { in: FEEDBACKS }
  validates :priority, inclusion: { in: PRIORITIES }

  scope :published, -> { where(status: "published") }
  scope :visible_to_company, -> { published.where.not(company_feedback: %w[not_relevant already_doing]) }
end
