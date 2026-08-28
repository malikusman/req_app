# frozen_string_literal: true

module ConsultantRequirements
  # Puts a drafted question to the employee.
  #
  # Delivery goes through the existing ConsultantFollowup::SendService rather than a
  # third consultant -> employee channel: that already handles the 24h WhatsApp
  # window, the template fallback outside it, and message persistence. The link back
  # to the created request is what lets an inbound reply find this question, and
  # through it the requirement to re-evaluate.
  class SendQuestionService
    class BudgetExhausted < StandardError; end

    def self.call(question:, consultant:)
      new(question: question, consultant: consultant).call
    end

    def initialize(question:, consultant:)
      @question = question
      @consultant = consultant
      @package = question.discovery_package
      @employee = @package.employee
      @company = @package.company
    end

    def call
      raise ArgumentError, "Question already sent" unless @question.status.in?(%w[drafted queued])

      # Checked at send time, not draft time: drafts a consultant discarded should
      # not consume the employee's allowance.
      if Discovery::FollowupLimits.package_budget_remaining(@package).zero?
        raise BudgetExhausted,
              "This employee has already been asked the maximum number of follow-up questions."
      end

      result = ConsultantFollowup::SendService.call(
        consultant: @consultant,
        employee: @employee,
        body: @question.body,
        report: @package.conversation.company.reports.order(version: :desc).first
      )

      @question.update!(
        status: "sent",
        sent_at: Time.current,
        sent_message: result[:message],
        consultant_info_request: result[:request]
      )
      @question
    end
  end
end
