# frozen_string_literal: true

# A share link scoped to one rendering of a report.
#
# Sharing the executive brief and sharing the full report are different acts —
# the brief is the thing a client forwards, and a forwarded PDF must not drag
# fourteen pages of evidence behind it. One row per variant per report.
class ReportShare < ApplicationRecord
  belongs_to :report

  validates :variant, presence: true, inclusion: { in: -> (_) { Reports::VariantSpec::VARIANTS } }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def active?
    revoked_at.nil? && expires_at.present? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
