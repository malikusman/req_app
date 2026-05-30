# frozen_string_literal: true

module Whatsapp
  class SelfServeOnboardingHandler
    CACHE_PREFIX = "whatsapp/self_serve"
    CACHE_TTL = 24.hours
    HELLO_PATTERN = /\A(hi|hello|hey|hola|start|begin)\z/i
    # Fallback when cache_store is :null_store (e.g. test env)
    FALLBACK_STORE = Concurrent::Map.new

    def initialize(phone:, client: MetaClient.new)
      @phone = phone
      @client = client
    end

    def handle_inbound_text(text)
      text = text.to_s.strip
      state = read_state

      if state.blank?
        return prompt_for_join_code if text.blank? || HELLO_PATTERN.match?(text)

        company = Company.find_by_join_code(text)
        if company
          write_state(step: "awaiting_name", company_id: company.id)
          log_attempt(company: company, success: true)
          send_text(
            "You're joining #{company.display_name || company.name}. " \
            "What's your full name?"
          )
        else
          log_attempt(company: nil, success: false, reason: "invalid_company_code")
          send_text("That company code isn't valid. Please check the 5-character code from your admin and try again.")
        end
        return
      end

      case state["step"]
      when "awaiting_name"
        handle_name(text, state)
      when "awaiting_email"
        handle_email(text, state)
      else
        clear_state
        prompt_for_join_code
      end
    end

    private

    def handle_name(text, state)
      company = Company.find(state["company_id"])

      employee = if email_like?(text)
                   link_email_only_employee(company: company, email: text) || begin
                     send_text(
                       "We couldn't find an invitation for that email. Reply with your full name to join."
                     )
                     return
                   end
                 else
                   create_walk_in_employee(company: company, name: text)
                 end

      clear_state

      conversation = employee.conversations.create!(
        company: company,
        status: "onboarding",
        started_at: Time.current,
        last_activity_at: Time.current
      )

      OnboardingHandler.new(employee: employee, conversation: conversation, client: @client)
                       .send_welcome_after_self_serve(name: employee.display_name)
    end

    def handle_email(text, state)
      company = Company.find(state["company_id"])
      employee = link_email_only_employee(company: company, email: text)
      unless employee
        send_text("We couldn't find an invitation for that email. Reply with your full name to join as a new participant.")
        write_state(step: "awaiting_name", company_id: company.id)
        return
      end

      clear_state
      conversation = active_or_new_conversation(employee, company)
      employee.update!(display_name: employee.display_name.presence || text.split("@").first.titleize)
      OnboardingHandler.new(employee: employee, conversation: conversation, client: @client)
                       .send_welcome_after_self_serve(name: employee.display_name)
    end

    def link_email_only_employee(company:, email:)
      normalized = email.to_s.strip.downcase
      employee = company.employees.where(phone_e164: nil).where("LOWER(email) = ?", normalized).first
      return nil unless employee

      if Employee.where.not(id: employee.id).exists?(phone_e164: @phone)
        send_text("This phone number is already linked to another account. Contact your admin.")
        return nil
      end

      employee.update!(
        phone_e164: @phone,
        participation_status: "started",
        started_at: employee.started_at || Time.current,
        onboarding_step: "awaiting_name"
      )
      employee
    end

    def create_walk_in_employee(company:, name:)
      company.increment!(:invited_count)

      company.employees.create!(
        phone_e164: @phone,
        display_name: name,
        participation_status: "started",
        onboarding_step: "awaiting_name",
        started_at: Time.current
      )
    end

    def active_or_new_conversation(employee, company)
      conv = employee.conversations.where.not(status: "abandoned").order(created_at: :desc).first
      return conv if conv

      employee.conversations.create!(
        company: company,
        status: "onboarding",
        started_at: Time.current,
        last_activity_at: Time.current
      )
    end

    def email_like?(text)
      text.to_s.include?("@")
    end

    def prompt_for_join_code
      send_text(
        "Welcome to Req workflow discovery! Reply with your 5-character company code " \
        "(from your admin or invitation email) to get started."
      )
    end

    def read_state
      Rails.cache.read(cache_key) || FALLBACK_STORE[cache_key]
    end

    def write_state(step:, company_id:)
      payload = { "step" => step, "company_id" => company_id }
      Rails.cache.write(cache_key, payload, expires_in: CACHE_TTL)
      FALLBACK_STORE[cache_key] = payload
    end

    def clear_state
      Rails.cache.delete(cache_key)
      FALLBACK_STORE.delete(cache_key)
    end

    def cache_key
      "#{CACHE_PREFIX}/#{@phone}"
    end

    def log_attempt(company:, success:, reason: nil)
      return unless company

      AccessCodeVerificationAttempt.create!(
        company: company,
        phone_e164: @phone,
        success: success,
        failure_reason: reason
      )
    end

    def send_text(body)
      if @client.configured?
        @client.send_text(to: @phone, body: body)
      else
        Rails.logger.info("[WhatsApp dev] to=#{@phone} body=#{body}")
      end
    end
  end
end
