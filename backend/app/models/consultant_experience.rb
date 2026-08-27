# frozen_string_literal: true

class ConsultantExperience < ApplicationRecord
  belongs_to :consultant_user

  validates :organization, :title, :start_year, presence: true
  validates :start_year, numericality: { greater_than: 1970, less_than_or_equal_to: -> { Time.current.year + 1 } }
  validates :end_year, allow_nil: true, numericality: { greater_than_or_equal_to: :start_year }, if: :end_year?
end
