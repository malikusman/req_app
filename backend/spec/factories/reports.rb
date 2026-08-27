# frozen_string_literal: true

FactoryBot.define do
  factory :report do
    company
    sequence(:version) { |n| n }
    status { "ready" }
    visibility { "internal_only" }
    triggered_by_type { "CompanyUser" }
    triggered_by_id { create(:company_user, company: company).id }
    report_snapshot { {} }
    review_workflow_status { "awaiting_consultants" }

    trait :ready do
      status { "ready" }
      generated_at { Time.current }
      report_snapshot do
        {
          "company" => { "name" => company.display_name || company.name, "locale" => company.locale },
          "readiness" => { "score" => 80, "breakdown" => {} },
          "participation" => {},
          "signals" => [],
          "patterns" => [],
          "recommendations" => [],
          "supporting_media" => [],
          "generated_at" => Time.current.iso8601
        }
      end
    end
  end

  factory :report_review do
    report
    consultant_user
    company { report.company }
    status { "pending" }
  end

  factory :report_review_comment do
    report_review
    consultant_user { report_review.consultant_user }
    section_key { "signals" }
    sequence(:body) { |n| "Comment #{n}" }
  end
end
