# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationSession do
  let(:session) { create(:conversation_session) }

  it "keeps every state it moves through" do
    session.move_to("CONSENT")
    session.move_to("OPENING")
    session.save!

    expect(session.reload.state).to eq("OPENING")
    expect(session.state_history.map { |h| [h["from"], h["to"]] }).to eq([%w[NOT_STARTED CONSENT], %w[CONSENT OPENING]])
  end

  it "refuses a state that doesn't exist" do
    expect { session.move_to("IN_PROGRESS") }.to raise_error(ArgumentError)
  end

  it "leaves system notices out of the history a prompt sees" do
    create(:conversation_turn, session: session, turn_index: 1, direction: "AI", text: "Shall we start?")
    create(:conversation_turn, session: session, turn_index: 2, direction: "SYSTEM", text: "Give me a moment…",
                               is_system_notice: true)
    create(:conversation_turn, session: session, turn_index: 3, text: "Yes")

    expect(session.history.map(&:turn_index)).to eq([1, 3])
    expect(session.next_turn_index).to eq(4)
    expect(session.turns.last.locator).to eq("t3")
  end

  it "belongs to the engagement's company" do
    other = build(:conversation_session, company: create(:company))
    expect(other).not_to be_valid
  end

  it "numbers a person's sessions, one per version" do
    expect { create(:conversation_session, participant: session.participant, version: 1) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
