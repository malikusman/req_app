# frozen_string_literal: true

FactoryBot.define do
  factory :report do
    company
    version { 1 }
    status { "ready" }
    visibility { "internal_only" }
    review_workflow_status { "not_required" }
    triggered_by_type { "PlatformUser" }
    triggered_by_id { create(:platform_user).id }
    report_snapshot { {} }
  end
end
