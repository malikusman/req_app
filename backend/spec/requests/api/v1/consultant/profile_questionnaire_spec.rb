# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant profile questionnaire", type: :request do
  let(:consultant) { create(:consultant_user, status: "active", profile_status: "draft") }
  let(:headers) { auth_headers_for(consultant) }

  it "returns questionnaire progress on show" do
    get "/api/v1/consultant/profile", headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to have_key("completion_percent")
    expect(body).to have_key("questionnaire_answers")
    expect(body["profile"]["completeness"]).to have_key("questionnaire_percent")
  end

  it "saves questionnaire answers and syncs strengths/industries/experiences" do
    patch "/api/v1/consultant/profile/questionnaire",
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

    consultant.reload
    expect(consultant.headline).to eq("Ops leader, GCC")
    expect(consultant.expertise_tags).to include("Operations transformation")
    expect(consultant.industries).to include("Logistics & Transportation")
    expect(consultant.years_experience).to eq(11)
    expect(consultant.consultant_experiences.count).to eq(1)
    expect(consultant.consultant_experiences.first.organization).to eq("Acme")
  end

  it "allows publish even when credibility fields are incomplete" do
    patch "/api/v1/consultant/profile",
          params: { publish: true },
          headers: headers,
          as: :json

    expect(response).to have_http_status(:ok)
    expect(consultant.reload.profile_status).to eq("published")
  end
end
