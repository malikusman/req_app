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

  # A client that can carry a whole conversation: P02 asks one distinct question
  # per area or mode, and P03 finds every answer usable for the area it was asked
  # about, plus whatever extra the block adds to the capture.
  def self.scripted(turns: 200, &extra)
    ask = lambda do |context|
      area = context[/^Target: (\w+)/, 1]
      mode = context[/^Mode: (\w+)/, 1]
      case mode
      when "OPENING" then "Thank you for your time. I know the basics already, so I won't ask about them. Shall we start?"
      when "CLOSING" then "Thank you, that has been really helpful. We'll speak with your team next."
      when "PRIORITY_READ_BACK" then "So growth and approvals stand out. Which matters most to you?"
      else "Thanks. Tell me more about #{(area || mode).downcase.tr('_', ' ')} in #{mode.downcase.tr('_', ' ')} terms?"
      end
    end
    capture = lambda do |context|
      area = context[/^target: (\w+) —/, 1]
      turn_id = context[/turn_id="(t\d+)"/, 1]
      base = {
        "previous_target_result" => { "domain" => area, "quality" => area ? "USABLE" : "NONE" },
        "domains_touched" => area ? [{ "domain" => area, "contribution" => "USABLE" }] : [],
        "statements" => [], "participant_signal" => "NONE",
        "summary_update" => area ? "Said something useful about #{area.downcase}." : nil
      }
      extra ? extra.call(base, context, turn_id) : base
    end
    new(turns: Array.new(turns) { ask }, captures: Array.new(turns) { capture })
  end

  def configured? = true

  def key_person_turn(system:, context:) = reply(:turn, system, context)
  def key_person_capture(system:, context:) = reply(:capture, system, context)
  def key_person_context(system:, context:) = reply(:context, system, context)

  # allocate, not new: specs often stub Openai::Client.new to return this fake.
  def parse_reply(content) = Openai::Client.allocate.parse_reply(content)

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
