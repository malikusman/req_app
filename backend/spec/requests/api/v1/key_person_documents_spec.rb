# frozen_string_literal: true

require "rails_helper"

# Documents asked for at the end of a conversation with leadership (Doc 08 §14,
# Doc 14 §11), and kept away from everything that reads company documents.
RSpec.describe "Documents in a conversation with leadership", type: :request do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:user) { create(:company_user, company: company, name: "Layla Haddad", job_title: "CEO") }
  let(:headers) { auth_headers_for(user) }
  let!(:engagement) do
    create(:engagement, company: company, status: "KEY_PERSON_DISCOVERY", key_user: user,
                        planned_departments: [{ "name" => "Sales", "count" => 2 }])
  end
  let(:storage) { instance_double(Storage::MinioClient, upload: true) }
  let(:path) { "/api/v1/company/leadership" }
  let(:mentioned) { ["weekly sales pack", "org chart", "KPI sheet", "credit policy"] }
  let(:client) do
    docs = mentioned
    KeyPersonFakeClient.scripted do |capture, context, turn_id|
      first = context.include?('turn_id="t2"')
      capture.merge("documents_mentioned" => first ? docs.map { |d| { "description" => d, "evidence" => turn_id } } : [])
    end
  end

  before do
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow(Storage::MinioClient).to receive(:new).and_return(storage)
    KeyPerson::Kickoff.call(engagement)
    post "#{path}/consent", headers: headers
  end

  def say(text) = post("#{path}/messages", params: { text: text }, headers: headers, as: :json)

  def until_documents_asked
    40.times do
      break if response.parsed_body.dig("session", "document_requests").present?

      say("Something useful.")
    end
  end

  def pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 SENTINEL-KPI-PACK"), "application/pdf",
                                         original_filename: "kpi.pdf")

  it "asks for at most three of the documents mentioned, by name" do
    until_documents_asked

    requests = response.parsed_body["session"]["document_requests"]
    expect(requests.pluck("requested_item", "status")).to eq([["weekly sales pack", "REQUESTED"],
                                                              ["org chart", "REQUESTED"], ["KPI sheet", "REQUESTED"]])
    expect(DocumentRequest.first.evidence).to eq(["t2"])
  end

  it "stores an upload against its request, and keeps it out of the client's documents and analysis" do
    until_documents_asked
    request = DocumentRequest.find_by!(requested_item: "KPI sheet")

    post "#{path}/documents", params: { file: pdf, document_request_id: request.id }, headers: headers

    expect(response).to have_http_status(:created)
    document = Document.leadership.last
    expect(document).to have_attributes(document_request: request, status: "uploaded", sensitivity: "confidential")
    expect(request.reload.status).to eq("RECEIVED")
    expect(document.document_chunks).to be_empty
    expect(enqueued_jobs).to be_none { |j| j["job_class"].to_s.match?(/Parse|Ingest|Analysis/) }

    get "/api/v1/company/documents", headers: headers
    expect(response.parsed_body["documents"]).to be_empty
    get "/api/v1/company/documents/#{document.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "takes uploads after the conversation has ended" do
    until_documents_asked
    engagement.participants.find_by!(source: "KEY_USER").conversation_sessions.last.update!(state: "COMPLETE")

    post "#{path}/documents", params: { file: pdf }, headers: headers
    expect(response).to have_http_status(:created)
  end

  it "refuses a file it can't take" do
    until_documents_asked
    exe = Rack::Test::UploadedFile.new(StringIO.new("MZ"), "application/x-msdownload", original_filename: "a.exe")
    post "#{path}/documents", params: { file: exe }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context "when they can't share them" do
    let(:client) do
      docs = mentioned
      KeyPersonFakeClient.scripted do |capture, context, turn_id|
        capture = capture.merge("documents_mentioned" => context.include?('turn_id="t2"') ? docs.map { |d| { "description" => d, "evidence" => turn_id } } : [])
        context.include?("none (DOCUMENT_REQUEST)") ? capture.merge("participant_signal" => "UNWILLING_ON_TOPIC") : capture
      end
    end

    it "closes the requests, so nobody is reminded about them" do
      until_documents_asked
      say("Sorry, those are confidential.")
      expect(DocumentRequest.pluck(:status).uniq).to eq(["DECLINED"])
    end
  end
end
