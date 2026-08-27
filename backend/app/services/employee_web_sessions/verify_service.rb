# frozen_string_literal: true

module EmployeeWebSessions
  class VerifyService
    class Error < StandardError; end
    class InvalidSession < Error; end
    class AlreadyStarted < Error; end
    class RateLimited < Error; end
    class LimitReached < Error; end

    MAX_ATTEMPTS = 5
    WINDOW = 15.minutes

    def self.call(token:, ip_address: nil)
      new(token: token, ip_address: ip_address).call
    end

    def initialize(token:, ip_address: nil)
      @token = token
      @ip_address = ip_address
    end

    def call
      session = ResolveService.call(token: @token)
      raise InvalidSession, "Invalid or expired link" unless session

      enforce_rate_limit!(session)
      raise AlreadyStarted, "This link was already used" if session.verified_at.present?

      employee = session.employee
      if employee.onboarding_step.in?(%w[awaiting_access_code awaiting_name awaiting_company])
        step = employee.display_name.present? ? "awaiting_consent" : "awaiting_name"
        attrs = { onboarding_step: step }
        attrs[:verified_at] = Time.current if step == "awaiting_consent"
        employee.update!(attrs)
      end

      session.update!(verified_at: Time.current, last_seen_at: Time.current, ip_address: @ip_address)
      conversation = ensure_conversation!(employee)
      Web::TurnRouter.bootstrap!(employee: employee, conversation: conversation)

      {
        token: issue_jwt(session, employee),
        expires_at: session.expires_at,
        employee: employee_payload(employee),
        conversation: conversation_payload(conversation),
        messages: visible_messages(conversation).map { |m| message_json(m) }
      }
    end

    private

    def enforce_rate_limit!(session)
      count = Rails.cache.read(rate_limit_key(session)).to_i
      raise RateLimited if count >= MAX_ATTEMPTS

      Rails.cache.write(rate_limit_key(session), count + 1, expires_in: WINDOW)
    end

    def rate_limit_key(session)
      "discover_start:#{@ip_address}:#{session.token_digest.first(12)}"
    end

    def ensure_conversation!(employee)
      conv = employee.conversations.where.not(status: "abandoned").order(created_at: :desc).first
      return conv if conv

      company = employee.company
      unless Subscriptions::ConversationLimitEnforcer.can_start_discovery?(company: company)
        raise LimitReached, "Discovery conversation limit reached for this organization"
      end

      conversation = employee.conversations.create!(
        company: company,
        status: "onboarding",
        started_at: Time.current,
        last_activity_at: Time.current
      )
      Subscriptions::ConversationLimitEnforcer.record_discovery_started!(
        company: company,
        conversation: conversation
      )
      conversation
    end

    def issue_jwt(session, employee)
      JsonWebToken.encode(
        {
          sub: "employee:#{employee.id}",
          aud: "employee_web",
          employee_id: employee.id,
          web_session_id: session.id,
          company_id: employee.company_id,
          jti: SecureRandom.uuid
        },
        expires_at: session.expires_at
      )
    end

    def employee_payload(employee)
      {
        id: employee.id,
        display_name: employee.display_name,
        onboarding_step: employee.onboarding_step,
        participation_status: employee.participation_status
      }
    end

    def conversation_payload(conversation)
      {
        id: conversation.id,
        status: conversation.status,
        question_count: conversation.question_count
      }
    end

    # Mirrors EmployeeWebAuthenticatable#visible_messages — consultant follow-ups
    # included, system plumbing excluded.
    def visible_messages(conversation)
      conversation.messages
                  .employee_visible
                  .order(:created_at)
    end

    def message_json(message)
      {
        id: message.id,
        direction: message.direction,
        message_type: message.message_type,
        body: message.body,
        is_discovery_question: message.is_discovery_question,
        track: message.track,
        created_at: message.created_at
      }
    end
  end
end
