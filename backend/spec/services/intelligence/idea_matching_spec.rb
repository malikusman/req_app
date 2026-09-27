# frozen_string_literal: true

require "rails_helper"

RSpec.describe Intelligence::IdeaMatching do
  it "treats the same idea in different words as one" do
    expect(described_class.same?("Auto-DataSync Assistant", "SmartDataSync Agent")).to be(true)
    expect(described_class.same?("Operations Task Automation Scheduler", "Operations Task Automation Bot")).to be(true)
    expect(described_class.same?("Cross-System Data Reconciliation Agent", "Automated Cross-System Reconciliation Bot")).to be(true)
    expect(described_class.same?("OpsTask Automation Bot", "Operations Task Automator")).to be(true)
  end

  it "keeps different ideas apart" do
    expect(described_class.same?("TMS-to-SAP Billing Automator", "TMS-WMS Data Bridge Agent")).to be(false)
    expect(described_class.same?("Approval Data Extractor & Validator", "Approval Workflow Automation Agent")).to be(false)
    expect(described_class.same?("AI Agent", "Smart Bot")).to be(false) # nothing but generic words
  end
end

RSpec.describe Intelligence::AgenticIdeaUpsertService do
  let(:company) { create(:company) }

  def run(*titles) = described_class.call(company: company, ideas: titles.map { |t| { title: t, summary: "s" } })

  it "refreshes a reworded idea instead of adding it, and archives drafts the run did not produce" do
    run("Auto-DataSync Assistant", "Approval Concierge Agent")
    run("SmartDataSync Agent")

    active = company.agentic_ideas.active_backlog
    expect(active.pluck(:title)).to eq(["Auto-DataSync Assistant"])
    expect(company.agentic_ideas.where(status: "archived").pluck(:title)).to eq(["Approval Concierge Agent"])
  end

  it "never touches or duplicates a published idea" do
    run("Auto-DataSync Assistant")
    company.agentic_ideas.first.update!(status: "published", summary: "edited by a consultant")
    run("Auto-Data Sync Bot")

    expect(company.agentic_ideas.count).to eq(1)
    expect(company.agentic_ideas.first).to have_attributes(status: "published", summary: "edited by a consultant")
  end
end
