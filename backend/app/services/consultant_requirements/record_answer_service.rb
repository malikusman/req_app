# frozen_string_literal: true

module ConsultantRequirements
  # An employee answered a consultant's follow-up. Attribute it, then decide whether
  # the underlying need is settled and draft the next question if not.
  #
  # Called from the inbound path, so it must never raise: the employee's reply is
  # already persisted by the time we get here, and losing it to an exception in the
  # evaluation step would be far worse than an unevaluated requirement.
  class RecordAnswerService
    def self.call(question:, message:)
      new(question: question, message: message).call
    end

    def initialize(question:, message:)
      @question = question
      @message = message
      @requirement = question.consultant_requirement
    end

    def call
      @question.update!(status: "answered", answered_message: @message, answered_at: Time.current)
      return @question unless @requirement

      evaluate!
      @question
    rescue StandardError => e
      Rails.logger.error("[ConsultantRequirements::RecordAnswer] question=#{@question.id} #{e.class}: #{e.message}")
      @question
    end

    private

    def evaluate!
      verdict = Langgraph::Client.new.evaluate_requirement!(
        statement: @requirement.statement,
        answers: @requirement.answers.map { |a| { question: a[:question], answer: a[:answer] } },
        language: @requirement.employee.preferred_language.presence || @requirement.company.locale || "en"
      )

      if verdict["satisfied"]
        @requirement.satisfy!(basis: "agent_judged")
        return
      end

      @requirement.update!(
        status: "partially_satisfied",
        missing_aspects: Array(verdict["missing_aspects"])
      )

      # Only draft again if budget remains. Without this an unsatisfiable requirement
      # keeps asking until the employee disengages. Enqueued so the employee's
      # inbound message is not held open by a model call.
      DraftRequirementQuestionsJob.perform_later(@requirement.id)
    rescue Langgraph::UnavailableError => e
      # Leave it open for the consultant to judge by eye rather than guessing.
      Rails.logger.warn("[ConsultantRequirements::RecordAnswer] evaluation unavailable: #{e.message}")
      @requirement.update!(
        status: "partially_satisfied",
        missing_aspects: ["Answer received but could not be assessed automatically."]
      )
    end
  end
end
