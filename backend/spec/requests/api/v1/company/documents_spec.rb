# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Company::Documents", type: :request do
  let!(:company) { create(:company, :onboarded) }
  let!(:company_user) { create(:company_user, company: company, role: "company_admin") }

  before do
    minio = instance_double(Storage::MinioClient, upload: true)
    allow(Storage::MinioClient).to receive(:new).and_return(minio)
  end

  def uploaded_file(name:, content_type:, body:)
    tempfile = Tempfile.new([File.basename(name, ".*"), File.extname(name)])
    tempfile.binmode
    tempfile.write(body)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, content_type, original_filename: name)
  end

  describe "POST /api/v1/company/documents" do
    it "accepts docx uploads for processing" do
      file = uploaded_file(
        name: "manual.docx",
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        body: "fake-docx-content"
      )

      post "/api/v1/company/documents",
           params: { file: file, department: "operations" },
           headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("document", "filename")).to eq("manual.docx")
      expect(response.parsed_body.dig("document", "status")).to eq("pending")
    end

    it "stores category and admin_description in metadata" do
      file = uploaded_file(
        name: "org.pdf",
        content_type: "application/pdf",
        body: "%PDF-1.4 fake"
      )

      post "/api/v1/company/documents",
           params: {
             file: file,
             category: "org_chart",
             admin_description: "Leadership structure for operations"
           },
           headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:created)
      doc = Document.find(response.parsed_body.dig("document", "id"))
      expect(doc.metadata["category"]).to eq("org_chart")
      expect(doc.metadata["admin_description"]).to eq("Leadership structure for operations")
      expect(response.parsed_body.dig("document", "category")).to eq("org_chart")
    end

    it "rejects unsupported file types" do
      file = uploaded_file(name: "script.exe", content_type: "application/octet-stream", body: "binary")

      post "/api/v1/company/documents", params: { file: file }, headers: auth_headers_for(company_user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Unsupported file type")
    end
  end
end
