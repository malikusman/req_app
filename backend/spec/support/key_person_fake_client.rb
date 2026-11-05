# frozen_string_literal: true

# Stands in for Openai::Client in the conversation with leadership: hands back
# queued replies per step and remembers what each prompt contained, so a spec can
# check what reached the model as well as what the platform did with the reply.
class KeyPersonFakeClient
  attr_reader :calls

  def initialize(turns: [], captures: [], contexts: [])
    @queues = { turn: turns.dup, capture: captures.dup, context: contexts.dup }
    @calls = []
  end

  def configured? = true

  def key_person_turn(system:, context:) = reply(:turn, system, context)
  def key_person_capture(system:, context:) = reply(:capture, system, context)
  def key_person_context(system:, context:) = reply(:context, system, context)

  def parse_reply(content) = Openai::Client.new.parse_reply(content)

  def prompts(step) = calls.select { |c| c[:step] == step }

  private

  # A queued reply may be a String, a Hash (sent as JSON), an exception class to
  # raise, or a Proc given the context.
  def reply(step, system, context)
    @calls << { step: step, system: system, context: context }
    item = @queues[step].shift
    raise item if item.is_a?(Class) && item <= Exception

    content = item.is_a?(Proc) ? item.call(context) : item
    content = content.to_json if content.is_a?(Hash)
    Openai::Client::ChatResult.new(content: content.to_s, model: "fake", finish_reason: "stop", input_tokens: 10,
                                   output_tokens: 5, latency_ms: 1, escalated: false)
  end
end
