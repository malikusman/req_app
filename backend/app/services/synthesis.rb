# frozen_string_literal: true

# Consolidation and synthesis (Doc 10): see Synthesis::Run for one pass over an
# engagement, and Synthesis::ForTaskIntelligence / Synthesis::ForReport for what
# later stages read from it.
module Synthesis
  # Which model client an engagement's synthesis uses. Outside production a
  # company can be set to scripted replies (the demo and the browser tests), so
  # the whole flow runs without a model: the company setting
  # synthesis_scripted_replies, or SYNTHESIS_SCRIPTED_REPLIES=1 for a process.
  def self.client_for(company)
    scripted = !Rails.env.production? &&
               (ENV["SYNTHESIS_SCRIPTED_REPLIES"] == "1" ||
                company&.merged_settings&.dig("synthesis_scripted_replies") == true)
    scripted ? ScriptedClient.new : Openai::Client.new
  end

  def self.system_prompt(file)
    [Openai::Client.prompt("p00a_analytical_base.v1.txt").strip, Openai::Client.prompt(file).strip].join("\n\n")
  end
end
