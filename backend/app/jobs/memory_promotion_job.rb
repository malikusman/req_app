# frozen_string_literal: true

# Promotes high-confidence shared findings from a completed conversation's
# blackboard into company long-term memory (company_memory_facts), embedding
# them for cross-employee retrieval when OpenAI is configured.
class MemoryPromotionJob < ApplicationJob
  queue_as :default

  MIN_CONFIDENCE = 0.6

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    findings = conversation.blackboard["shared_findings"] || []
    return if findings.empty?

    employee = conversation.employee
    company = conversation.company
    openai = Openai::Client.new

    findings.each do |finding|
      content = finding["finding"].to_s.strip
      next if content.blank?
      next if finding["confidence"].to_f < MIN_CONFIDENCE
      next if company.company_memory_facts.exists?(conversation_id: conversation.id, content: content)

      embedding = openai.configured? ? safe_embedding(openai, content) : nil

      begin
        company.company_memory_facts.create!(
          employee: employee,
          conversation: conversation,
          fact_type: "finding",
          department: employee.department,
          content: content,
          confidence: finding["confidence"].to_f,
          source_agent: finding["agent"],
          embedding: embedding,
          metadata: { "turn" => finding["turn"] }
        )
      rescue ActiveRecord::RecordNotUnique
        # Concurrent promotion run already inserted this fact.
        next
      end
    end
  end

  private

  def safe_embedding(openai, content)
    openai.embedding(content)
  rescue StandardError => e
    Rails.logger.warn("[MemoryPromotion] embedding failed: #{e.message}")
    nil
  end
end
