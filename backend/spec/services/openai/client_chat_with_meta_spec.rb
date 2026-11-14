# frozen_string_literal: true

require "rails_helper"

RSpec.describe Openai::Client, "#chat_with_meta" do
  let(:client) { described_class.new }
  let(:url) { "https://api.openai.com/v1/chat/completions" }
  let(:body) { { model: "gpt-test", messages: [{ role: "user", content: "Hi" }], max_tokens: 100 } }

  def reply(content, finish: "stop", usage: { prompt_tokens: 12, completion_tokens: 5 })
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: { model: "gpt-test-2026", usage: usage,
              choices: [{ finish_reason: finish, message: { content: content } }] }.to_json }
  end

  before { allow(client).to receive(:api_key).and_return("sk-test") }

  it "returns the reply with its model, tokens, finish reason and time taken" do
    stub_request(:post, url).to_return(reply("Hello"))

    result = client.send(:chat_with_meta, body)

    expect(result).to have_attributes(content: "Hello", model: "gpt-test-2026", finish_reason: "stop",
                                      input_tokens: 12, output_tokens: 5, escalated: false)
    expect(result.latency_ms).to be >= 0
  end

  it "asks once more with twice the cap when the reply was cut off" do
    stub_request(:post, url).with { |r| JSON.parse(r.body)["max_completion_tokens"] == 100 }.to_return(reply("Hel", finish: "length"))
    stub_request(:post, url).with { |r| JSON.parse(r.body)["max_completion_tokens"] == 200 }.to_return(reply("Hello there"))

    result = client.send(:chat_with_meta, body)

    expect(result).to have_attributes(content: "Hello there", finish_reason: "stop", escalated: true)
  end

  it "asks for JSON when told to" do
    stub_request(:post, url).with { |r| JSON.parse(r.body)["response_format"] == { "type" => "json_object" } }
                            .to_return(reply('{"ok":true}'))

    expect(client.send(:chat_with_meta, body, json: true).content).to eq('{"ok":true}')
  end

  it "raises on a failed call, for the caller to log" do
    stub_request(:post, url).to_return(status: 500, body: { error: { message: "upstream" } }.to_json)

    expect { client.send(:chat_with_meta, body) }.to raise_error(Openai::Client::Error, /upstream/)
  end
end
