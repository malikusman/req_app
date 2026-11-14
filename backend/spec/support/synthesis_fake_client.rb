# frozen_string_literal: true

# Stands in for Openai::Client in synthesis: hands back queued replies per step
# (a Hash is sent as JSON, a String as-is, a lambda is called with the context)
# and remembers every prompt, so a spec can check what reached the model as
# well as what the platform did with the reply.
class SynthesisFakeClient
  attr_reader :calls

  def initialize(relationships: [], syntheses: [])
    @queues = { relationship: relationships.dup, synthesis: syntheses.dup }
    @calls = []
  end

  def configured? = true

  def process_relationship(system:, context:) = reply(:relationship, system, context)
  def synthesis(system:, context:) = reply(:synthesis, system, context)

  # allocate, not new: specs may stub Openai::Client.new to return this fake.
  def parse_reply(content) = Openai::Client.allocate.parse_reply(content)

  def contexts(step) = @calls.select { |c| c[:step] == step }.map { |c| c[:context] }

  private

  def reply(step, system, context)
    @calls << { step: step, system: system, context: context }
    queued = @queues[step].shift
    raise Openai::Client::Error, "no reply queued for #{step}" if queued.nil?

    content = queued.respond_to?(:call) ? queued.call(context) : queued
    content = content.to_json unless content.is_a?(String)
    Openai::Client::ChatResult.new(content: content, model: "fake", finish_reason: "stop", input_tokens: 10,
                                   output_tokens: 5, latency_ms: 1, escalated: false)
  end
end
