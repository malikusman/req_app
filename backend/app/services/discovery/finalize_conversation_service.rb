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

      first_completion = @employee.participation_status != "completed"
      snapshot = @conversation.state_snapshot.merge("finalized_at" => Time.current.iso8601)

      @conversation.update!(
        status: "completed",
        completed_at: Time.current,
        last_activity_at: Time.current,
        state_snapshot: snapshot
      )

      if first_completion
        @employee.update!(
          participation_status: "completed",
          completed_at: Time.current,
          last_active_at: Time.current
        )

        @company.increment!(:completed_count)
        @company.increment!(:conversation_count)
        Intelligence::TimelineRecorder.interview_completed!(company: @company, employee: @employee)
        NotificationService.notify_interview_completed(company: @company, employee: @employee)
      else
        @employee.update!(last_active_at: Time.current)
      end

      # Always re-aggregate / promote memory so late addendum insights are included (FEAT-ADDMORE).
      # Company-scoped so obsolete signals can be pruned as the employee cohort grows.
      AggregateIntelligenceJob.perform_later(@company.id)
      MemoryPromotionJob.perform_later(@conversation.id)
      # The consultant handover. Async because it makes an LLM call, and the
      # employee's final message must not wait on it. Re-runs after an addendum so
      # the package reflects the extra evidence, minting a new version.
      BuildDiscoveryPackageJob.perform_later(@conversation.id)
    end
  end
end
