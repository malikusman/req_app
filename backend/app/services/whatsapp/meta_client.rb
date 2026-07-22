# frozen_string_literal: true

module Whatsapp
  class MetaClient
    class ApiError < StandardError
      attr_reader :response

      def initialize(message, response: nil)
        super(message)
        @response = response
      end
    end

    def initialize
      @token = ENV.fetch("META_WHATSAPP_TOKEN", nil)
      @phone_number_id = ENV.fetch("META_PHONE_NUMBER_ID", nil)
      @api_version = ENV.fetch("META_API_VERSION", "v21.0")
    end

    def configured?
      @token.present? && @phone_number_id.present?
    end

    def send_text(to:, body:)
      post_messages(
        messaging_product: "whatsapp",
        to: normalize_to(to),
        type: "text",
        text: { body: body }
      )
    end

    def send_template(to:, template_name:, language_code: "en", components: [])
      payload = {
        messaging_product: "whatsapp",
        to: normalize_to(to),
        type: "template",
        template: {
          name: template_name,
          language: { code: language_code },
          components: components
        }
      }
      post_messages(payload)
    end

    def send_invitation_template(to:, employee_name:, company_name:)
      template_name = ENV.fetch("META_TEMPLATE_EMPLOYEE_INVITE", "employee_discovery_invite")
      send_template(
        to: to,
        template_name: template_name,
        language_code: "en",
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: employee_name.presence || "there" },
              { type: "text", text: company_name },
              { type: "text", text: ENV.fetch("META_WHATSAPP_DISPLAY_NUMBER", "our WhatsApp bot") }
            ]
          }
        ]
      )
    end

    def send_reviewer_followup_template(to:, employee_name:, company_name:)
      template_name = ENV.fetch("META_TEMPLATE_REVIEWER_FOLLOWUP", "reviewer_followup_reopen")
      send_template(
        to: to,
        template_name: template_name,
        language_code: "en",
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: employee_name.presence || "there" },
              { type: "text", text: company_name }
            ]
          }
        ]
      )
    end

    def send_typing_on(message_id:)
      return { "success" => false, "skipped" => "not_configured" } unless configured?
      return { "success" => false, "skipped" => "missing_message_id" } if message_id.blank?

      post_messages(
        messaging_product: "whatsapp",
        status: "read",
        message_id: message_id,
        typing_indicator: { type: "text" }
      )
    end

    def send_nudge_template(to:, employee_name:, company_name:)
      template_name = ENV.fetch("META_TEMPLATE_EMPLOYEE_NUDGE", "employee_discovery_nudge")
      send_template(
        to: to,
        template_name: template_name,
        language_code: "en",
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: employee_name.presence || "there" },
              { type: "text", text: company_name }
            ]
          }
        ]
      )
    end

    private

    def post_messages(payload)
      raise ApiError, "WhatsApp not configured" unless configured?

      uri = URI("https://graph.facebook.com/#{@api_version}/#{@phone_number_id}/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 30
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = http.request(request)
      body = JSON.parse(response.body) rescue {}

      unless response.is_a?(Net::HTTPSuccess)
        WhatsappDeliveryMetric.record!("api_error", metadata: { status: response.code, body: body })
        raise ApiError.new(body.dig("error", "message") || response.message, response: body)
      end

      body
    end

    def normalize_to(phone)
      phone.to_s.gsub(/\D/, "")
    end
  end
end
