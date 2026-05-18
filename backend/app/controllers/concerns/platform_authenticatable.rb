# frozen_string_literal: true

module PlatformAuthenticatable
  extend ActiveSupport::Concern
  include PunditAuthorizable

  included do
    pundit_context do
      AuthorizationContext.new(actor: current_platform_user, audience: :platform)
    end
    before_action :authenticate_platform_user!
  end

  private

  def authenticate_platform_user!
    payload = decoded_token
    unless payload && payload[:aud] == "platform"
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    user_id = payload[:sub].to_s.split(":").last.to_i
    @current_platform_user = PlatformUser.find_by(id: user_id, jti: payload[:jti])
    render json: { error: "Unauthorized" }, status: :unauthorized unless @current_platform_user
  end

  def current_platform_user
    @current_platform_user
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
end
