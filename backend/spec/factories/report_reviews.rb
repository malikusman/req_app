# frozen_string_literal: true

FactoryBot.define do
  factory :report_review do
    report
    reviewer_user
    company { report.company }
    status { "pending" }
  end
end
