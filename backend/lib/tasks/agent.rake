# frozen_string_literal: true

namespace :knowledge do
  desc "Backfill knowledge chunk embeddings for all companies (or COMPANY_ID=)"
  task backfill_embeddings: :environment do
    company_id = ENV["COMPANY_ID"]&.to_i
    Knowledge::BackfillEmbeddingsJob.perform_now(company_id.presence)
    puts "Backfill complete"
  end
end

namespace :agent do
  desc "Run agent eval harness (mock mode when OPENAI_API_KEY unset)"
  task eval: :environment do
    puts "Agent eval harness"
    puts "- Discovery: ProcessTurnService with multi_agent_discovery flag"
    puts "- RAG: Knowledge::SemanticSearch smoke test"
    company = Company.first
    if company
      results = Knowledge::SemanticSearch.call(company: company, query: "workflow automation")
      puts "  Semantic search returned #{results.size} results for #{company.name}"
    end
    uri = URI("#{ENV.fetch('LANGGRAPH_URL', 'http://localhost:8000')}/health")
    response = Net::HTTP.get_response(uri)
    puts "  LangGraph health: #{response.code} #{response.body}"
    puts "Eval complete"
  end
end
