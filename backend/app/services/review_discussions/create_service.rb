# frozen_string_literal: true

module ReviewDiscussions
  class CreateService
    def self.call(reviewer:, report:, params:)
      new(reviewer: reviewer, report: report, params: params).call
    end

    def initialize(reviewer:, report:, params:)
      @reviewer = reviewer
      @report = report
      @company = report.company
      @params = params
    end

    def call
      discussion = ReviewDiscussion.create!(
        report: @report,
        company: @company,
        author_reviewer_user: @reviewer,
        target_type: @params.fetch(:target_type),
        target_reviewer_user_id: @params[:target_reviewer_user_id],
        employee_id: @params[:employee_id],
        conversation_id: @params[:conversation_id],
        anchor_type: @params.fetch(:anchor_type),
        anchor_id: @params.fetch(:anchor_id).to_s,
        body: @params.fetch(:body),
        parent_id: @params[:parent_id],
        status: "open"
      )

      if discussion.target_type == "employee"
        # Consent gate: only WhatsApp the employee directly when the company allows
        # reviewer→employee contact (default on). When off, the reviewer's question
        # is still recorded, but must go through the admin-approved outreach path
        # instead of reaching the employee ungated.
        if @company.merged_settings["reviewer_can_contact_employees"] != false
          employee = @company.employees.find(discussion.employee_id)
          result = ReviewerFollowup::SendService.call(
            reviewer: @reviewer,
            employee: employee,
            body: discussion.body,
            report: @report
          )
          result[:request].update!(
            message_id: @params[:message_id],
            review_discussion: discussion
          )
        end
      elsif discussion.target_type == "reviewer" && discussion.target_reviewer_user_id.present?
        recipient = ReviewerUser.find(discussion.target_reviewer_user_id)
        NotificationService.notify_discussion_mention(
          recipient: recipient,
          company: @company,
          report: @report,
          author: @reviewer,
          discussion: discussion
        )
      end

      discussion
    end
  end
end
