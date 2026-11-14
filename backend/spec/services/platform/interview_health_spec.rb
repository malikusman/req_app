# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::InterviewHealth do
  let(:company) { create(:company) }

  def interview(status:, close: nil, questions: 6, quiet: false)
    create(:conversation, company: company, employee: create(:employee, company: company), status: status,
                          question_count: questions, last_activity_at: quiet ? 2.days.ago : Time.current,
                          state_snapshot: { "blackboard" => { "close_reason" => close }.compact })
  end

  it "counts how interviews are going and flags what needs a look" do
    interview(status: "completed", close: "dossier_complete", questions: 8)
    interview(status: "completed", close: "stalled", questions: 4)
    interview(status: "abandoned", close: "stalled", questions: 3)
    interview(status: "discovery", quiet: true)
    done = interview(status: "completed", close: "dossier_complete", questions: 9)
    10.times { |i| done.messages.create!(direction: "outbound", channel: "web", message_type: "text", body: "q#{i}",
                                          routing_decision: { "capture" => i < 2 ? "degraded" : "recorded" }) }

    row = described_class.call.find { |r| r[:company][:id] == company.id }

    expect(row[:interviews]).to include(started: 5, completed: 3, abandoned: 1, in_progress: 1, quiet: 1)
    expect(row[:closes]).to eq("dossier_complete" => 2, "stalled" => 2)
    expect(row[:median_questions]).to eq(8)
    expect(row[:capture]).to eq(turns: 10, fallbacks: 2)
    expect(row[:flags]).to include("1 in progress but quiet for over a day",
                                   "2 of 10 answers were not recorded",
                                   "2 of 4 interviews ended without covering the role")
  end
end
