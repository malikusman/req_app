# frozen_string_literal: true

# One change to a company fact after onboarding was submitted: which field, what
# it was and became, where the new value came from, and who made the change.
# Written by Companies::ProfileUpdater; read by consultants and Mjadi staff only.
class ProfileChange < ApplicationRecord
  belongs_to :company
  belongs_to :actor, polymorphic: true, optional: true

  validates :field, :source, presence: true

  def self.recent_json(company, limit: 20)
    company.profile_changes.includes(:actor).order(created_at: :desc, id: :desc).limit(limit).map do |change|
      {
        id: change.id,
        field: change.field,
        from: change.from_value,
        to: change.to_value,
        source: change.source,
        actor: change.actor && { type: change.actor_type, name: change.actor.try(:name) },
        at: change.created_at
      }
    end
  end
end
