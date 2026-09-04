# frozen_string_literal: true

module Companion
  # Non-interview companion reply (ask / help / casual). No insights / finalize.
  class ProcessTurnService
    FALLBACK = {
      "en" => "I'm here if you want tips, tools, or to share anything from your day. " \
              "If it should count for the company report, say \"add this to my interview\".",
      "es" => "Aquí estoy si quieres tips, herramientas, o compartir algo de tu día. " \
              "Si debe contar para el reporte, di \"add this to my interview\".",
      "fr" => "Je suis là pour des conseils, des outils, ou partager votre journée. " \
              "Pour le rapport, dites \"add this to my interview\".",
      "de" => "Ich bin da für Tipps, Tools oder Themen aus deinem Tag. " \
              "Für den Report sag \"add this to my interview\"."
    }.freeze

    def self.call(conversation:, employee:, user_message:, intent:)
      new(
        conversation: conversation,
        employee: employee,
        user_message: user_message,
        intent: intent
      ).call
    end

    def initialize(conversation:, employee:, user_message:, intent:)
      @conversation = conversation
      @employee = employee
      @company = employee.company
      @user_message = user_message
      @intent = intent.to_s
    end

    def call
      reply = generate_reply
      NoteStore.append_note!(conversation: @conversation, body: @user_message, intent: @intent)

      {
        "assistant_message" => reply,
        "completed" => true,
        "question_count" => @conversation.question_count,
        "insight" => {},
        "routing_decision" => {
          "action" => "companion",
          "agent" => "companion",
          "intent" => @intent
        },
        "active_agent_id" => "companion"
      }
    end

    private

    # The model call lives in the agent, not here: Rails assembles the context and
    # the agent reasons, the same split discovery uses. There used to be a second,
    # never-wired companion implementation in Python alongside this one -- both were
    # added in the same commit and this is the consolidation onto one.
    def generate_reply
      lang = (@employee.preferred_language.presence || @company.locale || "en").to_s
      result = Langgraph::Client.new.companion_turn!(
        user_message: @user_message,
        intent: @intent,
        language: lang,
        context: build_context
      )

      if result["generated_by"] == "deterministic"
        # The agent never raises for a companion turn — it returns its canned line and
        # says why. Without surfacing that, a model failing every turn is
        # indistinguishable from one doing its job.
        Rails.logger.warn(
          "[Companion::ProcessTurn] conversation=#{@conversation.id} " \
          "agent fell back to a canned reply: #{result['fallback_reason']}"
        )
      end

      text = result["assistant_message"].to_s.strip
      return text if text.present?

      FALLBACK[lang] || FALLBACK["en"]
    rescue Langgraph::UnavailableError => e
      # Includes the 503 the agent returns when the shared breaker is open.
      Rails.logger.warn("[Companion::ProcessTurn] agent unavailable: #{e.message}")
      FALLBACK[lang] || FALLBACK["en"]
    rescue StandardError => e
      Rails.logger.warn("[Companion::ProcessTurn] #{e.class}: #{e.message}")
      FALLBACK[lang] || FALLBACK["en"]
    end

    def build_context
      insights = @conversation.conversation_insights.order(created_at: :desc).limit(5).filter_map do |i|
        i.summary.presence
      end
      memory = CompanyMemoryFact.where(company: @company, employee: @employee)
                                .order(created_at: :desc)
                                .limit(5)
                                .pluck(:content)

      {
        "company_name" => @company.display_name || @company.name,
        "employee_name" => @employee.display_name.to_s,
        "department" => @employee.department,
        "job_title" => @employee.role_title,
        "recent_insights" => insights,
        "memory_facts" => memory,
        "companion_notes" => Array(NoteStore.companion_state(@conversation)["notes"]).last(3)
      }.compact
    end
  end
end
