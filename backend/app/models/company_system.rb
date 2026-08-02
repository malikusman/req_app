# frozen_string_literal: true

class CompanySystem < ApplicationRecord
  belongs_to :company

  CATEGORIES = %w[erp spreadsheet tms messaging crm finance warehouse other].freeze
  SOURCES = %w[manual inferred_employee inferred_document].freeze

  validates :name, :normalized_name, :category, :source, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :source, inclusion: { in: SOURCES }
  validates :normalized_name, uniqueness: { scope: :company_id }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :active, -> { where(active: true) }

  before_validation :normalize_name!

  def self.normalize(name)
    name.to_s.strip.downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  private

  def normalize_name!
    self.normalized_name = self.class.normalize(name) if name.present?
  end
end
