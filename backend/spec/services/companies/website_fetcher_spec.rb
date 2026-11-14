# frozen_string_literal: true

require "rails_helper"

RSpec.describe Companies::WebsiteFetcher do
  let(:fixtures) { Rails.root.join("spec/fixtures/websites") }
  let(:base) { "https://example-trading.ae" }

  before { allow(Resolv).to receive(:getaddresses).and_return(["93.184.216.34"]) }

  def serve(path, fixture = nil, status: 200)
    stub_request(:get, "#{base}#{path}").to_return(status: status, body: fixture ? fixtures.join(fixture).read : "")
  end

  describe "#pages" do
    before do
      serve("/", "trading_home.html")
      serve("/about-us", "trading_about.html")
      serve("/contact", "trading_contact.html")
      serve("/products", status: 404)
      serve("/careers", status: 500)
    end

    let(:pages) { described_class.new.pages("#{base}/") }

    it "reads the home page and the same-site pages worth reading, skipping ones that fail" do
      expect(pages.map(&:url)).to eq(["#{base}/", "#{base}/about-us", "#{base}/contact"])
      expect(WebMock).not_to have_requested(:get, "#{base}/brochure.pdf")
      expect(WebMock).not_to have_requested(:get, %r{facebook\.com})
    end

    it "keeps the footer apart from the body, where the address usually is" do
      home = pages.first
      expect(home.chrome).to include("Deira, Dubai, UAE", "Riyadh")
      expect(home.text).to include("wholesalers of tailoring materials")
      expect(home.text).not_to include("Deira", "tracking")
    end
  end

  it "follows Arabic link text to the pages it needs" do
    stub_request(:get, "#{base}/").to_return(body: fixtures.join("arabic_home.html").read)
    about = "#{base}/%D9%85%D9%86-%D9%86%D8%AD%D9%86"
    stub_request(:get, about).to_return(body: "<html><body><main>نبذة عن الشركة</main></body></html>")
    stub_request(:get, %r{#{base}/%D8%A7%D8%AA%D8%B5%D9%84}).to_return(status: 404)

    pages = described_class.new.pages("#{base}/")

    expect(pages.map(&:url)).to include(about)
    expect(pages.first.text).to include("مستلزمات الخياطة")
  end

  it "says so when the home page can't be read" do
    serve("/", status: 503)
    expect { described_class.new.pages("#{base}/") }.to raise_error(described_class::Unreachable)
  end

  it "refuses private addresses" do
    allow(Resolv).to receive(:getaddresses).and_return(["10.0.0.5"])
    expect(described_class.new.fetch_html("http://intranet.example/")[:error]).to eq("unsafe_url")
  end
end
