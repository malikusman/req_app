# frozen_string_literal: true

module CompanyInfoRequests
  class CreateService
    def self.call(company:, requested_by:, subject:, body:, profile_section: nil, due_at: nil)
      new(company: company, requested_by: requested_by, subject: subject, body: body, profile_section: profile_section, due_at: due_at).call
    end

    def initialize(company:, requested_by:, subject:, body:, profile_section: nil, due_at: nil)
      @company = company
      @requested_by = requested_by
      @subject = subject
      @body = body
      @profile_section = profile_section.presence
      @due_at = due_at
    end

    def call
      request = CompanyInfoRequest.create!(
        company: @company,
        requested_by: @requested_by,
        subject: @subject,
        body: @body,
        profile_section: @profile_section,
        due_at: @due_at,
        status: "open"
      )

      NotificationService.notify_company_info_request_created(company: @company, request: request)
      request
    end
  end
end
