# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_company_user

    def connect
      payload = decode_token
      reject_unauthorized_connection unless payload && payload[:aud] == "company"

      user_id = payload[:sub].to_s.split(":").last.to_i
      @current_company_user = authenticate_user(payload, user_id)
      reject_unauthorized_connection unless @current_company_user
    end

    private

    def decode_token
      token = request.params[:token].presence || bearer_token
      JsonWebToken.decode(token) if token.present?
    end

    def bearer_token
      request.headers["Authorization"]&.match(/^Bearer (.+)$/)&.captures&.first
    end

    def authenticate_user(payload, user_id)
      if payload[:impersonation]
        CompanyUser.find_by(id: user_id, company_id: payload[:company_id], status: "active")
      else
        CompanyUser.find_by(
          id: user_id,
          company_id: payload[:company_id],
          jti: payload[:jti],
          status: "active"
        )
      end
    end
  end
end
