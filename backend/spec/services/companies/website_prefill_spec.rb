# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::WebsitePrefill do
  let(:company) { create(:company, name: "Example Trading LLC", website_url: "https://example-trading.ae") }
  let(:engagement) { create(:engagement, company: company, status: "ONBOARDING", languages: %w[ar en]) }
  let(:client) { instance_double(Openai::Client, configured?: true) }
  let(:home) { "https://example-trading.ae/" }
  let(:pages) do
    [Companies::WebsiteFetcher::Page.new(url: home, text: "Wholesalers of tailoring materials", chrome: "Deira, Dubai"),
     Companies::WebsiteFetcher::Page.new(url: "https://example-trading.ae/contact", text: "WhatsApp us", chrome: "")]
  end

  def candidate(field, value, **extra)
    { "field" => field, "value" => value, "display_text" => Array(value).join(", "), "confidence" => "HIGH",
      "source_url" => home, "evidence_excerpt" => "leading wholesalers of tailoring materials" }.merge(extra.stringify_keys)
  end

  def reply(*candidates, entity: "SINGLE_COMPANY", note: nil)
    { "entity_check" => { "website_describes" => entity, "note" => note }, "candidates" => candidates }
  end

  before do
    ENV["AI_PREFILL"] = "true"
    allow(Openai::Client).to receive(:new).and_return(client)
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
    allow_any_instance_of(Companies::WebsiteFetcher).to receive(:pages).and_return(pages)
  end

  it "stores evidenced proposals, never as facts" do
    allow(client).to receive(:website_prefill).and_return(reply(
      candidate("industry", "Wholesale distribution — tailoring materials"),
      candidate("customer_channels", %w[WHATSAPP phone FAX], source_url: "https://example-trading.ae/contact",
                                                             evidence_excerpt: "WhatsApp us"),
      candidate("locations", ["Dubai, UAE", "Riyadh, KSA"])
    ))

    described_class.call(engagement: engagement)

    expect(engagement.reload.prefill_status).to eq("done")
    rows = engagement.prefill_candidates.order(:id)
    expect(rows.map(&:target_field)).to eq(%w[industry customer_channels locations])
    expect(rows.second.value).to eq(%w[WHATSAPP PHONE]) # FAX isn't one of the channels
    expect(rows.map(&:status).uniq).to eq(["PROPOSED"])
    expect(rows.first).to have_attributes(fact_status: "INFERRED", prompt_version: "P01.v1",
                                          website_url: "https://example-trading.ae")
    expect(company.reload.company_profile).to eq({})
  end

  it "asks for proposals in the engagement's first language, from the fetched pages" do
    expect(client).to receive(:website_prefill)
      .with(hash_including(display_language: "Arabic", company_name: company.display_name,
                           pages: [hash_including(url: home), hash_including(text: "WhatsApp us")]))
      .and_return(reply)
    described_class.call(engagement: engagement)
  end

  describe "what is thrown away" do
    def stored_after(*candidates)
      allow(client).to receive(:website_prefill).and_return(reply(*candidates))
      described_class.call(engagement: engagement)
      engagement.prefill_candidates.pluck(:target_field)
    end

    it "drops evidence from a page that wasn't fetched, or no evidence at all" do
      expect(stored_after(candidate("industry", "Retail", source_url: "https://elsewhere.example/"),
                          candidate("products_services", "Fabrics", evidence_excerpt: " "))).to be_empty
    end

    it "drops evidence that is the model's reasoning rather than the page's words" do
      expect(stored_after(candidate("customer_channels", %w[IN_PERSON],
                                    evidence_excerpt: "Showroom photos imply customers visit in person"))).to be_empty
    end

    it "never keeps headcount, revenue or readiness, however it is labelled" do
      expect(stored_after(candidate("products_services", "Fabrics, with 5,000 employees"),
                          candidate("industry", "Trading", display_text: "Annual revenue AED 900m"),
                          candidate("headcount", "200"))).to be_empty
    end

    it "keeps departments, systems and AI tools only when the site shows them clearly" do
      expect(stored_after(candidate("departments", %w[Sales Finance], confidence: "LOW"),
                          candidate("core_systems", ["Shopify"], confidence: "MEDIUM"))).to eq(["core_systems"])
    end

    it "keeps one proposal per field and shortens the excerpt" do
      long = (["tailoring"] * 40).join(" ")
      stored_after(candidate("industry", "A", evidence_excerpt: long), candidate("industry", "B"))
      row = engagement.prefill_candidates.sole
      expect(row.value).to eq("A")
      expect(row.evidence_excerpt.split.size).to eq(25)
    end
  end

  it "notes a group website so the key user can say which entity this is" do
    allow(client).to receive(:website_prefill).and_return(reply(entity: "GROUP", note: "Site covers three brands"))
    described_class.call(engagement: engagement)
    expect(engagement.reload.prefill_entity_note).to eq("Site covers three brands")
  end

  it "replaces proposals nobody acted on, and keeps the client's decisions" do
    decided = engagement.prefill_candidates.create!(company: company, target_field: "industry", value: "Old",
                                                    confidence: "HIGH", source_url: home, evidence_excerpt: "x",
                                                    status: "CORRECTED", website_url: "https://example-trading.ae",
                                                    prompt_version: "P01.v1", extracted_at: 1.day.ago)
    stale = decided.dup.tap { |c| c.update!(status: "PROPOSED", target_field: "locations", value: ["Old"]) }
    allow(client).to receive(:website_prefill).and_return(reply(candidate("industry", "New")))

    described_class.call(engagement: engagement)

    expect(PrefillCandidate.exists?(stale.id)).to be(false)
    expect(decided.reload.status).to eq("CORRECTED")
  end

  describe "falling back to the plain form, without comment" do
    it "with no website" do
      company.update!(website_url: nil)
      described_class.call(engagement: engagement)
      expect(engagement.reload).to have_attributes(prefill_status: "empty", prefill_error: "no_website")
    end

    it "with the model switched off or not configured — never a made-up proposal" do
      ENV["AI_PREFILL"] = "false"
      described_class.call(engagement: engagement)
      expect(engagement.reload.prefill_status).to eq("empty")
      expect(engagement.prefill_candidates).to be_empty
    end

    it "after one retry when the reply isn't JSON" do
      calls = 0
      allow(client).to receive(:website_prefill) do
        calls += 1
        raise JSON::ParserError, "unexpected token"
      end
      described_class.call(engagement: engagement)
      expect(calls).to eq(2)
      expect(engagement.reload).to have_attributes(prefill_status: "empty", prefill_error: "unusable_reply")
    end

    it "when the model call fails" do
      allow(client).to receive(:website_prefill).and_raise(Openai::Client::Error, "boom")
      described_class.call(engagement: engagement)
      expect(engagement.reload.prefill_status).to eq("failed")
    end
  end

  it "discards the reading if the website changed meanwhile" do
    allow(client).to receive(:website_prefill) do
      company.update_columns(website_url: "https://new-site.example")
      reply(candidate("industry", "Trading"))
    end
    described_class.call(engagement: engagement)
    expect(engagement.prefill_candidates).to be_empty
  end

  describe WebsitePrefillJob do
    it "tries an unreachable site once more, then leaves the plain form" do
      allow_any_instance_of(Companies::WebsiteFetcher).to receive(:pages)
        .and_raise(Companies::WebsiteFetcher::Unreachable, "fetch_failed")

      perform_enqueued_jobs { described_class.perform_later(engagement.id) }

      expect(engagement.reload).to have_attributes(prefill_status: "failed")
      expect(engagement.prefill_error).to start_with("unreachable")
    end
  end
end
