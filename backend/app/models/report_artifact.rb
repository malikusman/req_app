# frozen_string_literal: true

# One rendering of a reviewed Report. The full report and the executive brief are
# PROJECTIONS of the same snapshot and the same consultant overlay — never
# separate analyses. See Reports::VariantSpec for what each variant contains.
class ReportArtifact < ApplicationRecord
  belongs_to :report

  validates :variant, presence: true,
                      inclusion: { in: -> (_) { Reports::VariantSpec::VARIANTS } },
                      uniqueness: { scope: :report_id }

  scope :ready, -> { where.not(storage_key: nil) }

  def real_pdf?
    content_type == "application/pdf"
  end

  def spec
    Reports::VariantSpec.for(variant)
  end
end
