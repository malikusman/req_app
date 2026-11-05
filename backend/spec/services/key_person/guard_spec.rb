# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyPerson::Guard do
  def check(text, mode: "QUESTION", **opts) = described_class.check(text, mode: mode, **opts)

  it "lets a short single question through" do
    expect(check("That's useful. Where does work tend to pile up waiting for someone?")).to be_nil
  end

  it "refuses an empty or overlong turn" do
    expect(check("  ")).to eq("empty")
    expect(check("#{'word ' * 50}?")).to eq("too_long")
    expect(check("#{'word ' * 100}?", mode: "OPENING")).to be_nil
  end

  it "asks exactly one thing, except in the opening, read-back and closing" do
    expect(check("What slows you down? And who approves quotes?")).to eq("question_count")
    expect(check("Thanks, that helps.")).to eq("question_count")
    expect(check("Thank you for your time today.", mode: "CLOSING")).to be_nil
    expect(check("ما الذي يبطئ العمل؟")).to be_nil
  end

  it "never brings up AI, automation, price or reports on its own (P02 §12)" do
    expect(check("Would an AI agent that follows up quotes help?")).to eq("blocked_term:ai")
    expect(check("Which tasks could be automated?")).to eq("blocked_term:automation")
    expect(check("What would you expect to pay for this?")).to eq("blocked_term:price")
    expect(check("Is there a budget set aside for this?")).to eq("blocked_term:price")
    expect(check("How do you feel about the fees?")).to eq("blocked_term:price")
    expect(check("What should our report focus on?")).to eq("blocked_term:report")
    expect(check("هل تستخدمون الذكاء الاصطناعي؟")).to eq("blocked_term:ai")
  end

  it "may echo those words once the participant has used them" do
    said = "Our prices are under pressure and the weekly report is always late."
    expect(check("What makes the weekly report late?", participant_text: said)).to be_nil
    expect(check("Where are prices hurting most?", participant_text: said)).to be_nil
  end

  it "may name a report they mentioned when asking for documents" do
    expect(check("Could you share the weekly sales report you mentioned?", mode: "DOCUMENT_REQUEST")).to be_nil
  end

  it "never talks about consultants, readiness or assessments" do
    expect(check("Our consultants will review this — how ready are you?")).to eq("blocked_term:process")
    expect(check("How would you rate your readiness?")).to eq("blocked_term:process")
  end

  it "doesn't repeat a question, even reworded" do
    earlier = ["Where do you want the business to be in two years that it isn't today?"]
    expect(check("In two years, where do you want the business to be that it isn't today?",
                 recent_questions: earlier)).to eq("repeats_question")
    expect(check("What do your best customers complain about?", recent_questions: earlier)).to be_nil
    expect(check("Welcome back. Where do you want the business to be in two years that it isn't today?",
                 mode: "RESUME", recent_questions: earlier)).to be_nil
  end

  it "doesn't ask for what the company already told us" do
    expect(check("What industry are you in?", known_fields: %w[industry])).to eq("asks_known_fact:industry")
    expect(check("What industry are you in?", known_fields: [])).to be_nil
    expect(check("How many employees do you have?", known_fields: %w[size_band])).to eq("asks_known_fact:size_band")
  end
end
