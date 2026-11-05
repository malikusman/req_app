# frozen_string_literal: true

# The conversations with leadership (Doc 08): see KeyPerson::Turn for one step
# of a conversation and KeyPerson::Planner for how the next one is chosen.
module KeyPerson
  # Which model client a company's conversations use. Outside production, a
  # company can be set to scripted replies (the demo and the browser tests) so
  # the whole flow runs without a model: the company setting
  # key_person_scripted_replies, or KEY_PERSON_SCRIPTED_REPLIES=1 for a process.
  def self.client_for(company)
    scripted = !Rails.env.production? &&
               (ENV["KEY_PERSON_SCRIPTED_REPLIES"] == "1" ||
                company&.merged_settings&.dig("key_person_scripted_replies") == true)
    scripted ? ScriptedClient.new : Openai::Client.new
  end
end
