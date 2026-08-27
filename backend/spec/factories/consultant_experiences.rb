# frozen_string_literal: true

FactoryBot.define do
  factory :consultant_experience do
    consultant_user
    organization { "Acme Corp" }
    title { "Operations Director" }
    start_year { 2015 }
    end_year { 2022 }
    summary { "Led regional transformation programs." }
    sort_order { 0 }
  end
end
