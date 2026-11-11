# frozen_string_literal: true

# One piece of work in a cluster, with the variant or stage it belongs to and
# the finding as it stood when it was grouped. Findings are rebuilt in place, so
# the digest is how a later change shows up as a stale cluster rather than
# being trusted silently.
class ProcessClusterMember < ApplicationRecord
  belongs_to :process_cluster
  belongs_to :finding
  belongs_to :employee, optional: true

  validates :member_digest, presence: true

  # What a finding looks like for staleness: its wording, figures and status.
  def self.digest_for(finding)
    Digest::SHA256.hexdigest([finding.id, finding.updated_at.to_f, finding.draft_digest, finding.status].join("|"))
  end

  def stale? = finding.nil? || self.class.digest_for(finding) != member_digest
end
