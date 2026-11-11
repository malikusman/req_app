# frozen_string_literal: true

require "rails_helper"

# P24 explains a computed Stage 1 fee and writes the client's scope statement;
# it never prices (P24, Doc 17 §16). A reply that fails a check is dropped for
# the template, and the quote can still be approved (P24 §7–9).
RSpec.describe Pricing::Explainer do
  let(:company) do
    create(:company, company_profile: { "country" => "UAE", "industry" => "wholesale_distribution" },
                     questionnaire_answers: { "o05_products_services" => "SENTINEL-ANSWER" })
  end
  let(:engagement) do
    create(:engagement, company: company, status: "STAGE_1_PRICING", languages: %w[en ar],
                        planned_departments: [{ "name" => "Sales", "count" => 4 }, { "name" => "Finance", "count" => 2 }])
  end
  let(:quote) { Pricing::ProposeStage1.call(engagement).quote }

  # A model that replies with whatever it is given.
  let(:fake_model) do
    Class.new do
      attr_reader :contexts

      def initialize(replies)
        @replies = replies
        @contexts = []
      end

      def configured? = true

      def stage1_price_explanation(system:, context:)
        _ = system
        @contexts << context
        Openai::Client::ChatResult.new(content: @replies.shift, model: "fake", finish_reason: "stop", input_tokens: 10,
                                       output_tokens: 20, latency_ms: 5, escalated: false)
      end

      def parse_reply(content) = JSON.parse(content)
    end
  end

  before do
    Pricing::Defaults.ensure!
    allow(OpenaiCircuitBreaker).to receive(:open?).and_return(false)
  end

  def good_reply
    context = Pricing::Stage1Context.build(quote)
    Pricing::ScriptedClient.new.stage1_price_explanation(system: "", context: context).content
  end

  def explain(*replies)
    model = fake_model.new(replies)
    described_class.call(quote, client: model)
    model
  end

  def with(changes)
    reply = JSON.parse(good_reply)
    changes.each { |path, value| reply.dig(*path[0..-2])[path.last] = value }
    reply.to_json
  end

  it "explains the fee and writes the client's scope statement, quoting the figures exactly" do
    explain(good_reply)

    quote.reload
    expect(quote.explanation_source).to eq("P24")
    expect(quote.admin_explanation["derivation"].map { |d| d["amount"] })
      .to eq(quote.line_items.map { |l| Pricing::Money.format(l["amount"], "AED") })
    expect(quote.client_scope["what_is_included"]).to include(a_string_including("6 of your team"))
    expect(quote.client_scope["validity"]).to eq(Pricing::ScopeTemplate.call(quote)["validity"])
    expect(quote.events.map(&:event)).to include("explained")
    expect(AiRun.find_by(subject: quote)).to have_attributes(stage: "P24", status: "OK", prompt_version: "P24.v1")
  end

  it "sees only the pricing context — no conversation, finding, note or onboarding answer" do
    own = create(:engagement_participant, engagement: engagement, participant_type: "KEY_PERSON", name: "Huda",
                                          consultant_focus: "SENTINEL-FOCUS")
    session = create(:conversation_session, participant: own, state: "COMPLETE")
    create(:conversation_turn, session: session, turn_index: 1, text: "SENTINEL-TURN")

    model = explain(good_reply)

    context = model.contexts.first
    expect(context).not_to include("SENTINEL")
    expect(context).to include('<margin trust="INTERNAL_COMMERCIAL">', "AED 1,500")
    expect(context.scan(/<(\w+) trust=/).flatten).to eq(Pricing::Stage1Context::BLOCKS)
  end

  # P24 §6.3 and §9's critical failures.
  {
    "suggests a discount" => [%w[administrator_view headline], "AED 30,000, though we could go lower if they push back."],
    "invents a figure" => [%w[administrator_view headline], "AED 35,000 — driven by participants."],
    "claims no risks when there are signals" => [%w[administrator_view what_could_make_this_wrong], ["No significant risks identified."]],
    "puts internal effort in the client's text" => [%w[client_scope_statement what_is_included],
                                                    ["26 consultant hours of expert time at our standard rates"]],
    "uses methodology vocabulary with the client" => [%w[client_scope_statement deliverable], "An AI-generated deep dive report."]
  }.each do |failure, (path, value)|
    it "drops a reply that #{failure}, for the template" do
      explain(with(path => value))

      quote.reload
      expect(quote).to have_attributes(explanation_source: "TEMPLATE", admin_explanation: {})
      expect(quote.events.last).to have_attributes(event: "explanation_fallback")
      expect(quote.events.last.detail["reason"]).to eq("failed_checks")
      expect(AiRun.find_by(subject: quote)).to have_attributes(status: "FALLBACK", fallback_reason: "failed_checks")
    end
  end

  it "retries an unreadable reply once, then falls back, and the quote can still be approved" do
    explain("not json", "still not json")

    expect(AiRun.find_by(subject: quote)).to have_attributes(status: "FALLBACK", fallback_reason: "unusable_reply")
    Pricing::Review.new(actor: create(:platform_user)).approve(quote.reload)
    expect(quote.reload.status).to eq("ISSUED")
  end

  it "uses a second reply when the first won't parse" do
    explain("not json", good_reply)
    expect(AiRun.find_by(subject: quote).status).to eq("RETRIED")
  end

  it "leaves a quote alone once it is no longer with the administrator" do
    Pricing::Review.new(actor: create(:platform_user)).approve(quote)
    model = explain(good_reply)

    expect(model.contexts).to be_empty
    expect(quote.reload.explanation_source).to eq("TEMPLATE")
  end

  it "is asked for each new version" do
    expect { quote }.to have_enqueued_job(ExplainStage1QuoteJob)
  end
end
