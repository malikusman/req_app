# frozen_string_literal: true

module EmployeeWebAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_employee_web_session!
  end

  private

  def authenticate_employee_web_session!
    payload = decoded_token
    unless payload && payload[:aud] == "employee_web"
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    @current_employee_web_session = EmployeeWebSession.active.find_by(
      id: payload[:web_session_id],
      employee_id: payload[:employee_id],
      company_id: payload[:company_id]
    )
    unless @current_employee_web_session&.verified?
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    @current_employee = @current_employee_web_session.employee
    @current_employee_web_session.touch_seen!(ip_address: request.remote_ip)
  end

  def current_employee
    @current_employee
  end

  def current_employee_web_session
    @current_employee_web_session
  end

  def current_conversation
    @current_conversation ||= begin
      conv = current_employee.conversations.where.not(status: "abandoned").order(created_at: :desc).first
      conv || current_employee.conversations.create!(
        company: current_employee.company,
        status: "onboarding",
        started_at: Time.current,
        last_activity_at: Time.current
      )
    end
  end

  def decoded_token
    token = bearer_token
    JsonWebToken.decode(token) if token.present?
  end

  def bearer_token
    pattern = /^Bearer (.+)$/
    header = request.headers["Authorization"]
    header&.match(pattern)&.captures&.first
  end

  def visible_messages
    current_conversation.messages
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

  def state_json
    conversation = current_conversation
    employee = current_employee
    {
      onboarding_step: employee.onboarding_step,
      participation_status: employee.participation_status,
      conversation_status: conversation.status,
      question_count: conversation.question_count,
      completed: conversation.status == "completed"
    }
  end
end
