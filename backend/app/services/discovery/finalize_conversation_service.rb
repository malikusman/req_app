# frozen_string_literal: true

module Discovery
  class FinalizeConversationService
    def self.call(conversation:, employee:)
      new(conversation: conversation, employee: employee).call
    end

    def initialize(conversation:, employee:)
      @conversation = conversation
      @employee = employee
      @company = employee.company
    end

    def call
      return if @conversation.status == "completed"

      @conversation.update!(
        status: "completed",
        completed_at: Time.current,
        last_activity_at: Time.current
      )

      return if @employee.participation_status == "completed"

      @employee.update!(
        participation_status: "completed",
        completed_at: Time.current,
        last_active_at: Time.current
      )

      @company.increment!(:completed_count)
      @company.increment!(:conversation_count)
      Intelligence::TimelineRecorder.interview_completed!(company: @company, employee: @employee)
      AggregateIntelligenceJob.perform_later(@company.id, @employee.department)
      MemoryPromotionJob.perform_later(@conversation.id)

      NotificationService.notify_interview_completed(company: @company, employee: @employee)
    end
  end
end
