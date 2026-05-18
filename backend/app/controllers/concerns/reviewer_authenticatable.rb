# frozen_string_literal: true

module ReviewerAuthenticatable
  extend ActiveSupport::Concern
  include PunditAuthorizable

  included do
    pundit_context do
      AuthorizationContext.new(actor: current_reviewer_user, audience: :reviewer)
    end
    before_action :authenticate_reviewer_user!
  end

  private

  def authenticate_reviewer_user!
    payload = decoded_token
    unless payload && payload[:aud] == "reviewer"
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    user_id = payload[:sub].to_s.split(":").last.to_i
    @current_reviewer_user = ReviewerUser.active.find_by(
      id: user_id,
      jti: payload[:jti]
    )
    render json: { error: "Unauthorized" }, status: :unauthorized unless @current_reviewer_user
  end

  def current_reviewer_user
    @current_reviewer_user
  end

  def assigned_company_ids
    @assigned_company_ids ||= current_reviewer_user.active_company_ids
  end

  def company_scope(relation)
    relation.where(company_id: assigned_company_ids)
  end

  def decoded_token
    token = bearer_token
    JsonWebToken.decode(token) if token.present?
  end

  def bearer_token
    request.headers["Authorization"]&.match(/^Bearer (.+)$/)&.captures&.first
  end
end
