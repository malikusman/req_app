# frozen_string_literal: true

require "rails_helper"

# The in-portal reader renders the report's HTML so it can offer real section
# jump links, which a scaled page image cannot. It serves the STORED html behind
# the approved PDF rather than a live re-render: a live one would drift the
# moment a consultant touched an override after approval, and could show the
# client an edit that was never approved.
RSpec.describe "Company report reader", type: :request do
  let(:company) { create(:company) }
  let(:company_user) { create(:company_user, company: company) }
  let(:headers) { auth_headers_for(company_user) }
  let(:report) do
    company.reports.create!(
      version: 3, status: "ready", visibility: "shared_with_company",
      review_workflow_status: "platform_approved",
      triggered_by_type: "CompanyUser", triggered_by_id: company_user.id,
      storage_key: "reports/#{company.id}/v3/report.pdf", content_type: "application/pdf",
      report_snapshot: { "signals" => [] }, generated_at: Time.current
    )
  end

  def artifact!(variant:, reader_key: "reports/#{variant}.reader.html", content_type: "application/pdf")
    report.report_artifacts.create!(
      variant: variant, storage_key: "reports/#{variant}.pdf", content_type: content_type,
      reader_storage_key: reader_key, page_count: 4, generated_at: Time.current
    )
  end

  # MinioClient checks the bucket in its constructor, so the client itself is
  # doubled rather than just its #download.
  let(:storage) { instance_double(Storage::MinioClient) }

  before do
    allow(Storage::MinioClient).to receive(:new).and_return(storage)
    allow(storage).to receive(:download)
      .and_return("<html><body><section class='page'>Signals</section></body></html>")
  end

  it "serves the stored reader HTML as a document, not JSON" do
    artifact!(variant: "full")

    get "/api/v1/company/reports/#{report.id}/read", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("<section class='page'>")
  end

  it "serves the requested variant's own HTML" do
    artifact!(variant: "full")
    brief = artifact!(variant: "exec_brief")
    expect(storage).to receive(:download).with(brief.reader_storage_key).and_return("<html>brief</html>")

    get "/api/v1/company/reports/#{report.id}/read", params: { variant: "exec_brief" }, headers: headers

    expect(response.body).to eq("<html>brief</html>")
  end

  it "defaults to the full report when no variant is given" do
    full = artifact!(variant: "full")
    expect(storage).to receive(:download).with(full.reader_storage_key).and_return("<html>full</html>")

    get "/api/v1/company/reports/#{report.id}/read", headers: headers

    expect(response.body).to eq("<html>full</html>")
  end

  it "rejects an unknown variant rather than quietly serving the full report" do
    artifact!(variant: "full")

    get "/api/v1/company/reports/#{report.id}/read", params: { variant: "everything" }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "requires authentication" do
    artifact!(variant: "full")

    get "/api/v1/company/reports/#{report.id}/read"

    expect(response).to have_http_status(:unauthorized)
  end

  # The approval gate applies to the reader exactly as it does to the download.
  it "refuses a report that has not been shared with the company" do
    artifact!(variant: "full")
    report.update!(visibility: "internal_only")

    get "/api/v1/company/reports/#{report.id}/read", headers: headers

    expect(response).to have_http_status(:forbidden)
  end

  # ReportPolicy#download? already requires ready + shared_with_company for a
  # company user, so an unfinished report is refused by the policy before the
  # action's own guards run. Both are kept: the policy is the gate, the guards
  # give a readable reason if it ever loosens.
  it "refuses a report that is still generating" do
    artifact!(variant: "full")
    report.update!(status: "generating")

    get "/api/v1/company/reports/#{report.id}/read", headers: headers

    expect(response.status).to be_in([403, 404])
  end

  # Reports generated before reader HTML was stored, and reports whose PDF
  # generation fell back to HTML.
  context "when no reader HTML was stored" do
    it "points the reader at the PDF instead of failing opaquely" do
      artifact!(variant: "full", reader_key: nil)

      get "/api/v1/company/reports/#{report.id}/read", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to match(/download the PDF/i)
    end

    it "falls back to the artifact itself when Gotenberg produced HTML" do
      artifact!(variant: "full", reader_key: nil, content_type: "text/html")

      get "/api/v1/company/reports/#{report.id}/read", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end
  end
end
