# frozen_string_literal: true

module ReviewDiscussions
  class CreateService
    def self.call(consultant:, report:, params:)
      new(consultant: consultant, report: report, params: params).call
    end

    def initialize(consultant:, report:, params:)
      @consultant = consultant
      @report = report
      @company = report.company
      @params = params
    end

    def call
      discussion = ReviewDiscussion.create!(
        report: @report,
        company: @company,
        author_consultant_user: @consultant,
        target_type: @params.fetch(:target_type),
        target_consultant_user_id: @params[:target_consultant_user_id],
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
        # consultant→employee contact (default on). When off, the consultant's question
        # is still recorded, but must go through the admin-approved outreach path
        # instead of reaching the employee ungated.
        if @company.merged_settings["consultant_can_contact_employees"] != false
          employee = @company.employees.find(discussion.employee_id)
          result = ConsultantFollowup::SendService.call(
            consultant: @consultant,
            employee: employee,
            body: discussion.body,
            report: @report
          )
          result[:request].update!(
            message_id: @params[:message_id],
            review_discussion: discussion
          )
        end
      elsif discussion.target_type == "consultant" && discussion.target_consultant_user_id.present?
        recipient = ConsultantUser.find(discussion.target_consultant_user_id)
        NotificationService.notify_discussion_mention(
          recipient: recipient,
          company: @company,
          report: @report,
          author: @consultant,
          discussion: discussion
        )
      end

      discussion
    end
  end
end
