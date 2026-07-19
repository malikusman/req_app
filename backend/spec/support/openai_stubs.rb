# frozen_string_literal: true

# When OPENAI_API_KEY is present in the environment (e.g. dev containers),
# embedding calls go live instead of using mock mode. Stub them globally so
# the suite is deterministic regardless of env; individual specs can still
# register more specific stubs, which take precedence.
RSpec.configure do |config|
  config.before(:each) do
    stub_request(:post, "https://api.openai.com/v1/embeddings")
      .to_return(
        status: 200,
        body: { data: [{ embedding: Array.new(1536, 0.0) }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
