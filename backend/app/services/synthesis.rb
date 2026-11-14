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

  # Tells later stages synthesis changed (Doc 10 §17: task intelligence re-ranks
  # when effort changes). Task intelligence subscribes to "synthesis.changed";
  # the payload says which engagement, which run, and whether anything a figure
  # depends on moved.
  def self.changed!(run, effort_changed: true, reason: run.trigger)
    ActiveSupport::Notifications.instrument("synthesis.changed",
                                            engagement_id: run.engagement_id, synthesis_version: run.version,
                                            effort_changed: effort_changed, reason: reason)
  end

  def self.system_prompt(file)
    [Openai::Client.prompt("p00a_analytical_base.v1.txt").strip, Openai::Client.prompt(file).strip].join("\n\n")
  end
end
