# frozen_string_literal: true

# A reviewer's editorial change to a generated report: hide a built-in section,
# add an editorial note to one, or add a whole new custom section. Applied to the
# snapshot at regeneration time (the stored snapshot itself is never mutated), so
# the AI-generated body and expert edits stay distinguishable and auditable.
class ReportSectionOverride < ApplicationRecord
  ACTIONS = %w[hide edit add].freeze

  # Built-in sections a reviewer may hide or annotate. Keep in sync with the
  # section render order in views/reports/document.html.erb.
  BUILT_IN_SECTIONS = %w[
    executive_summary readiness company_context participation delta
    signals patterns implications recommendations roadmap opportunities
    tools_catalog supporting_media methodology
  ].freeze

  belongs_to :report
  belongs_to :reviewer_user

  validates :action, inclusion: { in: ACTIONS }
  validates :section_key, presence: true, if: -> { action.in?(%w[hide edit]) }
  validates :section_key, inclusion: { in: BUILT_IN_SECTIONS }, if: -> { action.in?(%w[hide edit]) && section_key.present? }
  validates :body, presence: true, if: -> { action.in?(%w[edit add]) }
  validates :title, presence: true, if: -> { action == "add" }

  scope :published, -> { where(published: true) }
  scope :for_report, ->(report) { where(report_id: report.id) }

  def custom_slug
    section_key.presence || "custom-#{id}"
  end
end
