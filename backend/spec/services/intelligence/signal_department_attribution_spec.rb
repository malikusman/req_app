# frozen_string_literal: true

require "rails_helper"

# The gap this closes: signals carried no department at all from interview
# evidence, so PatternDetector's cross-department rule -- one of only three ways
# a pattern can form -- could never fire. Reports showed "Patterns detected (0)"
# with healthy signals. See docs/SIGNAL_DEPARTMENT_ATTRIBUTION.md.
RSpec.describe "Signal department attribution" do
  let(:company) { create(:company) }

  def interview!(department:, body:)
    employee = create(:employee, company: company, department: department, participation_status: "completed")
    conversation = create(:conversation, employee: employee, company: company, status: "completed")
    create(:message, conversation: conversation, direction: "inbound", message_type: "text", body: body)
    employee
  end

  def document!(department:, text:)
    doc = company.documents.create!(
      filename: "#{department}-process.txt", content_type: "text/plain",
      storage_key: "docs/#{SecureRandom.hex(4)}", status: "ready", department: department,
      byte_size: text.bytesize
    )
    doc.document_chunks.create!(chunk_index: 0, content: text)
    doc
  end

  def signal(type)
    Intelligence::SignalExtractor.call(company: company).find { |s| s[:signal_type] == type }
  end

  it "attributes an interview-derived signal to the interviewee's department" do
    interview!(department: "finance", body: "We re-enter every invoice line into a spreadsheet by hand each Friday.")

    expect(signal("manual_process")[:departments]).to contain_exactly("finance")
  end

  # The case that makes a cross-department pattern possible.
  it "spans both departments when two teams describe the same friction" do
    interview!(department: "finance", body: "We re-enter every invoice line into a spreadsheet by hand.")
    interview!(department: "operations", body: "Order details get copy-pasted into Excel manually every morning.")

    expect(signal("manual_process")[:departments]).to contain_exactly("finance", "operations")
  end

  it "attributes a document-derived signal to the document's department" do
    document!(department: "procurement", text: "Buyers reconcile duplicate supplier records by hand in a spreadsheet.")

    expect(signal("manual_process")[:departments]).to include("procurement")
  end

  it "combines document and interview departments on one signal" do
    document!(department: "procurement", text: "Buyers reconcile duplicate records in a spreadsheet manually.")
    interview!(department: "finance", body: "I re-enter the same figures into Excel by hand.")

    expect(signal("manual_process")[:departments]).to contain_exactly("procurement", "finance")
  end

  it "attributes nothing when the evidence has no department on it" do
    interview!(department: nil, body: "We re-enter every invoice line into a spreadsheet by hand.")

    expect(signal("manual_process")[:departments]).to eq([])
  end

  # Derived text (insight summaries, memory facts, knowledge entries) corroborates
  # a signal but is not traceable to one team, so it must attribute nothing.
  it "does not attribute a department from corroborating derived text alone" do
    employee = interview!(department: "finance", body: "Nothing much to report today.")
    conversation = employee.conversations.first
    ConversationInsight.create!(
      conversation: conversation, company: company, employee: employee,
      turn_number: 1, summary: "Heavy manual spreadsheet work across the team."
    )

    # The rule matches on derived text only, so there is no primary evidence
    # naming a department.
    expect(signal("manual_process")&.dig(:departments)).to eq([])
  end

  describe "end to end, through the aggregation the report reads" do
    it "forms a cross-department pattern from two teams' interviews" do
      interview!(department: "finance", body: "We re-enter every invoice line into a spreadsheet by hand each Friday.")
      interview!(department: "operations", body: "Order details get copy-pasted into Excel manually every morning, it is tedious and slow.")

      signals = Intelligence::SignalExtractor.call(company: company)
      Intelligence::SignalUpsertService.call(company: company, signals: signals, reconcile_stale: true)
      patterns = Intelligence::PatternDetector.call(company: company)

      cross = patterns.find { |p| p[:title].to_s.match?(/across departments/i) }
      expect(cross).to be_present
      expect(cross[:departments]).to contain_exactly("finance", "operations")
    end

    # FinalizeConversationService calls AggregateIntelligenceJob with no
    # department, which used to mean interview-derived signals were never tagged.
    it "tags signals even though the interview path passes no department scalar" do
      interview!(department: "finance", body: "Approvals wait on a manager sign-off for days and we re-key everything manually.")

      Intelligence::AggregateCompanyIntelligence.call(company: company, department: nil)

      expect(company.company_signals.map(&:departments).flatten).to include("finance")
    end
  end
end
