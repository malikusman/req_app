# frozen_string_literal: true

class CompanySystem < ApplicationRecord
  belongs_to :company
  belongs_to :reviewer_user, optional: true

  CATEGORIES = %w[erp spreadsheet tms messaging crm finance warehouse other].freeze
  SOURCES = %w[manual inferred_employee inferred_document].freeze
  KINDS = %w[system owned_solution].freeze

  validates :name, :normalized_name, :category, :source, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :source, inclusion: { in: SOURCES }
  validates :kind, inclusion: { in: KINDS }
  validates :normalized_name, uniqueness: { scope: :company_id }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :active, -> { where(active: true) }
  scope :systems, -> { where(kind: "system") }
  scope :owned_solutions, -> { where(kind: "owned_solution") }

  def owned_solution?
    kind == "owned_solution"
  end

  before_validation :normalize_name!

  def self.normalize(name)
    name.to_s.strip.downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  private

  def normalize_name!
    self.normalized_name = self.class.normalize(name) if name.present?
  end
end
