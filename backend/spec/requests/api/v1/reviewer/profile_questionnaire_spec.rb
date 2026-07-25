# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reviewer profile questionnaire", type: :request do
  let(:reviewer) { create(:reviewer_user, status: "active", profile_status: "draft") }
  let(:headers) { auth_headers_for(reviewer) }

  it "returns questionnaire progress on show" do
    get "/api/v1/reviewer/profile", headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to have_key("completion_percent")
    expect(body).to have_key("questionnaire_answers")
    expect(body["profile"]["completeness"]).to have_key("questionnaire_percent")
  end

  it "saves questionnaire answers and syncs strengths/industries/experiences" do
    patch "/api/v1/reviewer/profile/questionnaire",
          params: {
            questionnaire_step: 5,
            questionnaire_answers: {
              headline: "Ops leader, GCC",
              bio: "A" * 85,
              linkedin_url: "https://linkedin.com/in/test",
              career_background: ["Big 4 (Deloitte, EY, KPMG, PwC)"],
              years_experience: "8–15 years",
              strengths: ["Operations transformation", "Supply chain", "Procurement"],
              industries_covered: ["Logistics & Transportation", "Manufacturing"],
              experiences: [
                { organization: "Acme", title: "Director", start_year: 2018, end_year: nil }
              ]
            }
          },
          headers: headers,
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["completion_percent"]).to be > 0
    expect(body["questionnaire_step"]).to eq(5)

    reviewer.reload
    expect(reviewer.headline).to eq("Ops leader, GCC")
    expect(reviewer.expertise_tags).to include("Operations transformation")
    expect(reviewer.industries).to include("Logistics & Transportation")
    expect(reviewer.years_experience).to eq(11)
    expect(reviewer.reviewer_experiences.count).to eq(1)
    expect(reviewer.reviewer_experiences.first.organization).to eq("Acme")
  end

  it "allows publish even when credibility fields are incomplete" do
    patch "/api/v1/reviewer/profile",
          params: { publish: true },
          headers: headers,
          as: :json

    expect(response).to have_http_status(:ok)
    expect(reviewer.reload.profile_status).to eq("published")
  end
end
