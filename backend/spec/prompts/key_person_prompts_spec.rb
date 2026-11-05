# frozen_string_literal: true

require "rails_helper"

# The prompt files (Doc 24). P00 is shared, so it must not drift between the
# engines that use it.
RSpec.describe "Prompt files" do
  def prompt(file) = Rails.root.join("app/prompts", file).read.delete("\r")

  it "keeps P01's preamble identical to the shared analytical base (P00-A)" do
    expect(prompt("p01_website_prefill.v1.txt")).to start_with(prompt("p00a_analytical_base.v1.txt").rstrip)
  end

  it "keeps the conversational base free of internal vocabulary it lists as forbidden (Doc 24 §5.5)" do
    base = prompt("p00c_conversational_base.v1.txt")
    expect(base).to include("{{language}}")
    expect(base).not_to match(/\b(pricing|margin|rate card)\b/i)
  end

  it "has a block for every mode the planner can ask for" do
    _, modes = KeyPerson::Interviewer.parse_rules
    asked = KeyPerson::Planner::QUESTION_MODES + KeyPerson::Planner::CLOSING_MODES + %w[OPENING HANDLE_ASIDE]
    expect(modes.keys).to include(*asked)
  end
end
