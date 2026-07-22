# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public reviewer applications", type: :request do
  let(:valid_params) do
    { name: "Alex Reviewer", email: "alex@reviewers.test", expertise_summary: "AP automation" }
  end

  it "creates a pending reviewer and enqueues emails" do
    expect {
      post "/api/v1/public/reviewer_applications", params: valid_params
    }.to change(ReviewerUser, :count).by(1)
      .and have_enqueued_mail(SignupMailer, :reviewer_application_received)
      .and have_enqueued_mail(SignupMailer, :reviewer_application_admin_notice)

    expect(response).to have_http_status(:created)
    expect(ReviewerUser.last.status).to eq("pending")
  end
end
