# frozen_string_literal: true

module Reviewer
  class CopilotService
    def self.call(reviewer:, company:, user_message:)
      new(reviewer: reviewer, company: company, user_message: user_message).call
    end

    def initialize(reviewer:, company:, user_message:)
      @reviewer = reviewer
      @company = company
      @user_message = user_message.to_s.strip
      @client = Langgraph::Client.new
    end

    def call
      raise ArgumentError, "message required" if @user_message.blank?
      raise Langgraph::UnavailableError, "feature_disabled" unless Companies::AgentFeatures.enabled?(@company, :reviewer_copilot)

      thread_id = copilot_thread_id
      history = prior_messages.map { |m| { role: m.role, content: m.body } }

      AgentCopilotMessage.create!(
        company: @company,
        reviewer_user: @reviewer,
        thread_id: thread_id,
        role: "user",
        body: @user_message
      )

      result = @client.reviewer_chat!(
        thread_id: thread_id,
        company_id: @company.id,
        user_message: @user_message,
        history: history
      )

      assistant = AgentCopilotMessage.create!(
        company: @company,
        reviewer_user: @reviewer,
        thread_id: thread_id,
        role: "assistant",
        body: result["assistant_message"].to_s,
        citations: result["citations"] || []
      )

      {
        message: assistant,
        citations: assistant.citations
      }
    end

    private

    def copilot_thread_id
      existing = AgentCopilotMessage.where(reviewer_user: @reviewer, company: @company).order(:created_at).last
      existing&.thread_id || SecureRandom.uuid
    end

    def prior_messages
      AgentCopilotMessage.where(reviewer_user: @reviewer, company: @company).order(:created_at).last(16)
    end
  end
end
