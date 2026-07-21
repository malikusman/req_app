# frozen_string_literal: true

class AgenticIdea < ApplicationRecord
  belongs_to :company
  belongs_to :solution_catalog_entry, optional: true, class_name: "SolutionCatalogEntry"

  STATUSES = %w[draft published archived].freeze
  SOURCES = %w[generated platform reviewer].freeze

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :draft, -> { where(status: "draft") }
  scope :published, -> { where(status: "published") }
  scope :active_backlog, -> { where(status: %w[draft published]) }

  def publish!(actor: nil)
    attrs = { status: "published", published_at: published_at || Time.current }
    if actor
      attrs[:updated_by_type] = actor.class.name
      attrs[:updated_by_id] = actor.id
    end
    update!(attrs)
  end

  def archive!(actor: nil)
    attrs = { status: "archived" }
    if actor
      attrs[:updated_by_type] = actor.class.name
      attrs[:updated_by_id] = actor.id
    end
    update!(attrs)
  end
end
