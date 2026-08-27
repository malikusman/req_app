# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public consultant applications", type: :request do
  let(:valid_params) do
    { name: "Alex Consultant", email: "alex@consultants.test", expertise_summary: "AP automation" }
  end

  it "creates a pending consultant and enqueues emails" do
    expect {
      post "/api/v1/public/consultant_applications", params: valid_params
    }.to change(ConsultantUser, :count).by(1)
      .and have_enqueued_mail(SignupMailer, :consultant_application_received)
      .and have_enqueued_mail(SignupMailer, :consultant_application_admin_notice)

    expect(response).to have_http_status(:created)
    expect(ConsultantUser.last.status).to eq("pending")
  end
end
