# frozen_string_literal: true

module CompanyAuthenticatable
  extend ActiveSupport::Concern
  include PunditAuthorizable

  included do
    pundit_context do
      AuthorizationContext.new(actor: current_company_user, audience: :company)
    end
    before_action :authenticate_company_user!
    before_action :require_active_subscription!
  end

  private

  def authenticate_company_user!
    payload = decoded_token
    unless payload && payload[:aud] == "company"
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    user_id = payload[:sub].to_s.split(":").last.to_i
    @current_company_user = if payload[:impersonation]
                              authenticate_impersonation(payload, user_id)
                            else
                              CompanyUser.find_by(
                                id: user_id,
                                company_id: payload[:company_id],
                                jti: payload[:jti],
                                status: "active"
                              )
                            end
    render json: { error: "Unauthorized" }, status: :unauthorized unless @current_company_user
  end

  def impersonating?
    @impersonation_session.present?
  end

  def impersonation_session
    @impersonation_session
  end

  def require_active_subscription!
    return if impersonating?
    return if current_company.subscription&.active_for_access?

    render json: { error: "Subscription inactive" }, status: :forbidden
  end

  def current_company_user
    @current_company_user
  end

  def current_company
    @current_company ||= current_company_user.company
  end

  def company_scope(relation)
    relation.where(company_id: current_company.id)
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

  def authenticate_impersonation(payload, user_id)
    session = ImpersonationSession.active.find_by(
      token_jti: payload[:jti],
      company_id: payload[:company_id],
      platform_user_id: payload[:platform_user_id]
    )
    return nil unless session

    @impersonation_session = session
    return nil unless session.company_user_id == user_id

    session.company_user
  end

end
