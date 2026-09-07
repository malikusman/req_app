# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportsHelper, type: :helper do
  describe "#report_rich_text" do
    # Consultant sections used to render as pre-wrap plain text on a bare page:
    # the part of the deliverable we sell looked worse than the machine's pages.
    it "renders scaffold markup as real headings, lists and emphasis" do
      body = <<~TEXT
        ## What I'd tell them

        Fix the **PO reconciliation** step first.

        - It costs nothing to try
        - It proves the finding is real
      TEXT

      html = helper.report_rich_text(body)

      expect(html).to include("<h4 class=\"rt-h rt-h2\">What I&#39;d tell them</h4>")
      expect(html).to include("<strong>PO reconciliation</strong>")
      expect(html).to include("<ul class=\"rt-list\">")
      expect(html).to include("<li>It costs nothing to try</li>")
    end

    it "escapes before introducing markup, so consultant input cannot inject HTML" do
      html = helper.report_rich_text("<script>alert(1)</script> and **bold**")

      expect(html).not_to include("<script>")
      expect(html).to include("&lt;script&gt;")
      expect(html).to include("<strong>bold</strong>")
    end

    it "returns nothing for blank input rather than an empty paragraph" do
      expect(helper.report_rich_text("   ")).to eq("")
    end

    # Bold runs first so an italic inside a bold run is not eaten by the
    # single-asterisk pass.
    it "handles italic and bold together" do
      html = helper.report_rich_text("*Mitigation.* Name one **concrete** step.")

      expect(html).to include("<em>Mitigation.</em>")
      expect(html).to include("<strong>concrete</strong>")
    end
  end

  describe "#report_evidence_line" do
    it "states the weight of evidence instead of quoting anybody" do
      line = helper.report_evidence_line(
        { "evidence_count" => 7, "departments" => %w[finance ops] }, docs_first: false
      )

      expect(line).to eq("Seen in 7 evidence points across 2 departments · interviews and documents")
    end

    it "names a single department rather than saying '1 department'" do
      line = helper.report_evidence_line({ "evidence_count" => 1, "departments" => ["Finance"] })

      expect(line).to eq("Seen in 1 evidence point across Finance · interviews and documents")
    end

    it "returns nil when there is nothing to attribute" do
      expect(helper.report_evidence_line({ "evidence_count" => 0, "departments" => [] })).to be_nil
    end
  end

  describe "#report_paginate" do
    it "chunks a list into page-sized groups" do
      expect(helper.report_paginate((1..7).to_a, 3)).to eq([[1, 2, 3], [4, 5, 6], [7]])
    end

    it "yields no pages for an empty list, so the section self-suppresses" do
      expect(helper.report_paginate([], 6)).to eq([])
    end

    # A zero would loop forever.
    it "never produces a zero-sized page" do
      expect(helper.report_paginate([1, 2], 0)).to eq([[1], [2]])
    end
  end

  describe "#report_amount" do
    it "formats a currency figure with its period" do
      expect(helper.report_amount(450_000, "AED / year")).to eq("AED 450,000 / year")
    end

    it "puts a non-currency unit after the number" do
      expect(helper.report_amount(1_200, "hours / year")).to eq("1,200 hours / year")
    end
  end

  describe "#report_evidence_base_sentence" do
    it "states coverage as method, without naming a single source" do
      sentence = helper.report_evidence_base_sentence(
        "evidence_base" => { "interviews" => 5, "documents" => 4, "media" => 1, "departments" => 3 }
      )

      expect(sentence).to eq("5 discovery interviews, 4 internal documents, and 1 media exhibit, spanning 3 departments")
    end

    it "returns nil when there is no evidence base recorded" do
      expect(helper.report_evidence_base_sentence({})).to be_nil
    end
  end
end
