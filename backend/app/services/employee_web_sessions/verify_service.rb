# frozen_string_literal: true

module EmployeeWebSessions
  class VerifyService
    class Error < StandardError; end
    class InvalidSession < Error; end
    class InvalidCode < Error; end
    class RateLimited < Error; end
    class LimitReached < Error; end

    MAX_ATTEMPTS = 5
    WINDOW = 15.minutes

    def self.call(token:, access_code:, ip_address: nil)
      new(token: token, access_code: access_code, ip_address: ip_address).call
    end

    def initialize(token:, access_code:, ip_address: nil)
      @token = token
      @access_code = access_code
      @ip_address = ip_address
    end

    def call
      session = ResolveService.call(token: @token)
      raise InvalidSession, "Invalid or expired link" unless session

      enforce_rate_limit!(session)
      employee = session.employee
      begin
        verify_access_code!(employee, @access_code)
      rescue InvalidCode
        record_failed_attempt!(session)
        raise
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
    end

    def record_failed_attempt!(session)
      key = rate_limit_key(session)
      count = Rails.cache.read(key).to_i
      Rails.cache.write(key, count + 1, expires_in: WINDOW)
    end

    def rate_limit_key(session)
      "discover_verify:#{@ip_address}:#{session.token_digest.first(12)}"
    end

    def verify_access_code!(employee, plain)
      normalized = plain.to_s.gsub(/\s+/, "").upcase
      raise InvalidCode, "Access code required" if normalized.blank?

      code_record = employee.employee_access_codes.order(created_at: :desc).first
      raise InvalidCode, "Invalid access code" unless code_record

      if employee.onboarding_step == "awaiting_access_code"
        if code_record.verify(normalized)
          code_record.update!(status: "used", used_at: Time.current)
          employee.update!(onboarding_step: "awaiting_consent", verified_at: Time.current)
          log_verification(employee, success: true)
          return
        end

        reason = code_record.expires_at.past? ? "expired" : "invalid_code"
        log_verification(employee, success: false, reason: reason)
        raise InvalidCode, "Invalid access code"
      end

      return if BCrypt::Password.new(code_record.code_digest) == normalized

      raise InvalidCode, "Invalid access code"
    end

    def log_verification(employee, success:, reason: nil)
      AccessCodeVerificationAttempt.create!(
        company: employee.company,
        employee: employee,
        phone_e164: employee.phone_e164,
        success: success,
        failure_reason: reason
      )
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

    def visible_messages(conversation)
      conversation.messages
                  .discovery_only
                  .where.not(message_type: "system")
                  .order(:created_at)
    end

    def message_json(message)
      {
        id: message.id,
        direction: message.direction,
        message_type: message.message_type,
        body: message.body,
        is_discovery_question: message.is_discovery_question,
        created_at: message.created_at
      }
    end
  end
end
