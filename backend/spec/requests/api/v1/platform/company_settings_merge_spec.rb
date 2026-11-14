# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform company settings", type: :request do
  let(:admin) { create(:platform_user) }
  let(:company) { create(:company, settings: { "allow_early_report" => true }) }

  it "merges a setting into the company's instead of replacing them all" do
    patch "/api/v1/platform/companies/#{company.id}",
          params: { company: { settings: { report_signals_placement: "hidden" } } },
          headers: auth_headers_for(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(company.reload.settings).to include("allow_early_report" => true, "report_signals_placement" => "hidden")
  end
end
