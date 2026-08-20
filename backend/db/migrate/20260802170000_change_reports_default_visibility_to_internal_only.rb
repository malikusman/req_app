# frozen_string_literal: true

# The old default ("shared_with_company") was a footgun: any report left at the
# default (e.g. a failed/edge row) was downloadable by policy. Reports are now
# gated by default — visibility is set explicitly to shared_with_company only on
# approval / skip_platform_review.
class ChangeReportsDefaultVisibilityToInternalOnly < ActiveRecord::Migration[7.1]
  def up
    change_column_default :reports, :visibility, from: "shared_with_company", to: "internal_only"
  end

  def down
    change_column_default :reports, :visibility, from: "internal_only", to: "shared_with_company"
  end
end
