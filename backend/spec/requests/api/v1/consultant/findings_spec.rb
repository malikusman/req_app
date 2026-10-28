# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consultant review of findings", type: :request do
  let(:company) { create(:company, :onboarded) }
  let(:consultant) { create(:consultant_user) }
  let(:headers) { auth_headers_for(consultant) }
  let!(:assignment) { create(:consultant_assignment, company: company, consultant_user: consultant, status: "active") }

  def finding(**attrs)
    Finding.create!({ company: company, source_key: SecureRandom.hex(4), area: "supplier price updates",
                      department: "procurement", role_title: "Procurement Officer",
                      friction: "Prices are re-keyed by hand", annual_hours_min: 160, annual_hours_max: 240 }.merge(attrs))
  end

  let!(:a) { finding }
  let!(:b) { finding(area: "price updates", role_title: "Buyer", annual_hours_min: 100, annual_hours_max: 150) }
  let!(:c) { finding(area: "purchase orders", single_occupant_role: true, annual_hours_min: nil, annual_hours_max: nil) }

  it "lists findings with de-duplicated totals and what still needs review" do
    get "/api/v1/consultant/companies/#{company.id}/findings", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["findings"].size).to eq(3)
    expect(body["summary"]).to include("live_count" => 3, "quantified_count" => 2,
                                       "annual_hours_min" => 260, "annual_hours_max" => 390,
                                       "needs_review_count" => 1)
  end

  it "stops counting a finding's hours once it is merged into the same work described by someone else" do
    post "/api/v1/consultant/companies/#{company.id}/findings/#{b.id}/merge", params: { into_id: a.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(b.reload).to have_attributes(status: "merged", merged_into_id: a.id, reviewed_by_id: consultant.id)

    get "/api/v1/consultant/companies/#{company.id}/findings", headers: headers
    summary = JSON.parse(response.body)["summary"]
    expect(summary).to include("live_count" => 2, "merged_count" => 1, "annual_hours_min" => 160, "annual_hours_max" => 240)
  end

  it "never lets merges chain" do
    post "/api/v1/consultant/companies/#{company.id}/findings/#{b.id}/merge", params: { into_id: a.id }, headers: headers
    post "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}/merge", params: { into_id: c.id }, headers: headers
    expect(b.reload.merged_into_id).to eq(c.id)
  end

  it "keeps the consultant's wording as an overlay and the interview's words intact" do
    patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
          params: { finding: { consultant_friction: "Supplier prices are re-keyed item by item into NAV", status: "approved" } },
          headers: headers

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)["finding"]
    expect(json["friction"]).to eq("Supplier prices are re-keyed item by item into NAV")
    expect(json["original"]["friction"]).to eq("Prices are re-keyed by hand")
    expect(json["status"]).to eq("approved")
  end

  it "keeps the consultant's cause and direction over the draft, as analysis unless they say otherwise" do
    a.update!(cause: "No import route", cause_stated: true, intervention_type: "integration_data_fix",
              direction: "Bring sheets in directly", draft_digest: a.draft_inputs_digest)
    patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
          params: { finding: { consultant_cause: "Layouts differ by supplier", consultant_intervention_type: "process_change",
                               consultant_direction: "Agree one sheet layout with suppliers" } },
          headers: headers

    json = JSON.parse(response.body)["finding"]
    expect(json.values_at("cause", "cause_stated", "intervention_type", "direction"))
      .to eq(["Layouts differ by supplier", false, "process_change", "Agree one sheet layout with suppliers"])
    expect(json["drafted"]["cause"]).to eq("No import route")
    expect(DraftFindingCausesJob).not_to have_been_enqueued
  end

  it "lets the consultant say who gave the cause without rewording it" do
    a.update!(cause: "Each supplier's sheet has its own layout", cause_stated: true, draft_digest: a.draft_inputs_digest)
    patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
          params: { finding: { consultant_cause_stated: false } }, headers: headers, as: :json

    json = JSON.parse(response.body)["finding"]
    expect(json.values_at("cause", "cause_stated")).to eq(["Each supplier's sheet has its own layout", false])

    patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
          params: { finding: { consultant_cause_stated: nil } }, headers: headers, as: :json
    expect(JSON.parse(response.body)["finding"]["cause_stated"]).to be(true)
  end

  describe "what must come first" do
    def save(**finding_params)
      patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
            params: { finding: finding_params }, headers: headers, as: :json
      JSON.parse(response.body)
    end

    it "keeps the consultant's dependency and links over the draft" do
      a.update!(dependency: "Codes are consistent", depends_on_ids: [b.id], draft_digest: a.draft_inputs_digest)
      json = save(consultant_dependency: "One sheet layout is agreed", consultant_depends_on_ids: [])["finding"]

      expect(json.values_at("dependency", "depends_on_ids")).to eq(["One sheet layout is agreed", []])
      expect(json["drafted"].values_at("dependency", "depends_on_ids")).to eq(["Codes are consistent", [b.id]])
    end

    it "follows the drafted links again when the consultant's are cleared" do
      a.update!(depends_on_ids: [b.id], consultant_depends_on_ids: [])
      expect(save(consultant_depends_on_ids: nil)["finding"]["depends_on_ids"]).to eq([b.id])
    end

    it "refuses a link that would close a loop" do
      b.update!(consultant_depends_on_ids: [a.id])
      body = save(consultant_depends_on_ids: [b.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["error"]).to include("would make a loop")
    end

    it "refuses a link to the finding itself, or to one set aside" do
      save(consultant_depends_on_ids: [a.id])
      expect(response).to have_http_status(:unprocessable_entity)

      b.update!(status: "hidden")
      save(consultant_depends_on_ids: [b.id])
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "redrafts the cause and direction when the wording changes" do
    a.update!(draft_digest: a.draft_inputs_digest)
    expect do
      patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
            params: { finding: { consultant_friction: "Price sheets are retyped line by line" } }, headers: headers
    end.to have_enqueued_job(DraftFindingCausesJob).with([a.id])
  end

  it "refuses a kind of change that is not on the list" do
    patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}",
          params: { finding: { consultant_intervention_type: "blockchain" } }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "clears the review flag once a single-occupant finding is approved" do
    patch "/api/v1/consultant/companies/#{company.id}/findings/#{c.id}", params: { finding: { status: "approved" } }, headers: headers
    expect(JSON.parse(response.body)["finding"]["needs_review"]).to be(false)
  end

  describe "correcting the figures" do
    let!(:po) do
      # The interview heard "per PO" and ten to fifteen minutes: no yearly volume, no hours.
      finding(area: "purchase orders", frequency_as_said: "per PO", frequency_unit: "per_event",
              duration_as_said: "10 to 15 minutes", duration_min: 10, duration_max: 15, duration_unit: "minutes")
    end

    def correct(effort)
      patch "/api/v1/consultant/companies/#{company.id}/findings/#{po.id}",
            params: { finding: { consultant_effort: effort } }, headers: headers, as: :json
    end

    it "works out hours from the consultant's figures, and keeps the interview's beside them" do
      expect(po.reload.hours?).to be(false)

      correct(frequency: { min: "15", unit: "per_week" }, duration: { min: "10", max: "15", unit: "minutes" })

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["finding"]
      expect(body["annual_hours"]).to eq("min" => 120, "max" => 180)
      expect(body["display_frequency"]).to eq("15 a week")
      expect(body["display_duration"]).to eq("10–15 minutes")
      expect(po.reload).to have_attributes(frequency_as_said: "per PO", frequency_unit: "per_event",
                                           reviewed_by_id: consultant.id)
      expect(po.hours_basis).to include("corrected" => true)
    end

    it "keeps the correction through a rebuild of the machine fields" do
      correct(frequency: { min: 15, unit: "per_week" }, duration: { min: 10, max: 15, unit: "minutes" })
      po.reload.update!(duration_min: 30, duration_max: 30) # what a rebuild from the interview does
      expect([po.annual_hours_min, po.annual_hours_max]).to eq([120, 180])
    end

    it "refuses figures it cannot work from" do
      correct(frequency: { min: "-2", unit: "per_week" }, duration: { min: "10", unit: "minutes" })
      expect(response).to have_http_status(:unprocessable_entity)

      correct(frequency: { min: "3", max: "2", unit: "per_week" }, duration: { min: "10", unit: "fortnights" })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("lower figure comes first", "needs a unit")
    end

    it "counts nothing when the consultant marks it as waiting" do
      correct(frequency: { min: 15, unit: "per_week" }, duration: { min: 2, unit: "days" }, effort_type: "waiting")
      expect(JSON.parse(response.body)["finding"]["annual_hours"]).to be_nil
    end

    it "puts the interview's figures back when the correction is cleared" do
      correct(frequency: { min: 15, unit: "per_week" }, duration: { min: 10, unit: "minutes" })
      correct(nil)
      body = JSON.parse(response.body)["finding"]
      expect(body["corrected_effort"]).to be_nil
      expect(body["annual_hours"]).to be_nil
      expect(body["display_frequency"]).to eq("per PO")
    end
  end

  it "does not accept merged as a plain status change" do
    patch "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}", params: { finding: { status: "merged" } }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "refuses to merge a finding into one from another company" do
    other = Finding.create!(company: create(:company, :onboarded), source_key: "x", area: "y")
    post "/api/v1/consultant/companies/#{company.id}/findings/#{a.id}/merge", params: { into_id: other.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "is not available for a company the consultant is not assigned to" do
    get "/api/v1/consultant/companies/#{create(:company, :onboarded).id}/findings", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
