# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Settings", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:user) { create(:company_user, company: company, role: "company_admin") }
  let(:headers) { auth_headers_for(user) }

  describe "PATCH /api/v1/company/settings/organization" do
    it "accepts Arabic locale" do
      patch "/api/v1/company/settings/organization",
            params: { locale: "ar", display_name: company.display_name },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(company.reload.locale).to eq("ar")
    end

    it "rejects invalid locale" do
      patch "/api/v1/company/settings/organization",
            params: { locale: "xx", display_name: company.display_name },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
