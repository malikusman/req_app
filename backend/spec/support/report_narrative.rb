# frozen_string_literal: true

# Keep the report snapshot deterministic in the suite: the LLM narrative writer
# would otherwise make a live chat/completions call whenever OPENAI_API_KEY is
# present in the environment (e.g. dev containers). Specs that exercise the
# writer enable it explicitly and stub the client.
RSpec.configure do |config|
  config.before(:each) do
    ENV["AI_REPORT_NARRATIVE"] = "false"
  end
end
