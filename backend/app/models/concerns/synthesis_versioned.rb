# frozen_string_literal: true

# Versioning shared by everything synthesis stores (Doc 06 §1.1–1.2): a change
# is a new row linked to the one it supersedes, never an edit in place, and the
# superseded row stays readable. Each model names the column that identifies
# one object across its versions (a cluster's key, an opportunity's key...).
module SynthesisVersioned
  extend ActiveSupport::Concern

  SUPERSEDED = "SUPERSEDED"

  included do
    belongs_to :parent_version, class_name: name, optional: true

    scope :current, -> { where.not(status: SUPERSEDED) }
  end

  class_methods do
    # The column that holds an object's identity across versions.
    def version_key(column = nil)
      column ? @version_key = column : @version_key
    end
  end

  def superseded? = status == SUPERSEDED

  # A new version carrying `changes`; this one is marked superseded. Returns the
  # new row. Models with child rows (a cluster's members) extend copy_children.
  def revise!(changes = {})
    raise ActiveRecord::RecordInvalid, self if superseded?

    self.class.transaction do
      lock!
      raise ActiveRecord::StaleObjectError.new(self, "revise") if superseded?

      copy = self.class.new(attributes.except("id", "created_at", "updated_at"))
      copy.assign_attributes(changes.merge(version: version + 1, parent_version_id: id))
      update!(status: SUPERSEDED)
      copy.save!
      copy_children(copy)
      copy
    end
  end

  private

  def copy_children(_copy); end
end
