# frozen_string_literal: true

module ConsultantAuthenticatable
  extend ActiveSupport::Concern
  include PunditAuthorizable

  included do
    pundit_context do
      AuthorizationContext.new(actor: current_consultant_user, audience: :consultant)
    end
    before_action :authenticate_consultant_user!
  end

  private

  # Tokens issued before the Reviewer -> Consultant rename carry aud "reviewer"
  # and live for 24h, so both are accepted for one release. `sub` needs no such
  # handling — it is parsed on the last ":" segment, so "reviewer_user:12" still
  # resolves to 12. Drop LEGACY_AUDIENCE once every pre-rename token has expired.
  ACCEPTED_AUDIENCES = %w[consultant reviewer].freeze

  def authenticate_consultant_user!
    payload = decoded_token
    unless payload && ACCEPTED_AUDIENCES.include?(payload[:aud])
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    user_id = payload[:sub].to_s.split(":").last.to_i
    @current_consultant_user = ConsultantUser.active.find_by(
      id: user_id,
      jti: payload[:jti]
    )
    render json: { error: "Unauthorized" }, status: :unauthorized unless @current_consultant_user
  end

  def current_consultant_user
    @current_consultant_user
  end

  def assigned_company_ids
    @assigned_company_ids ||= current_consultant_user.active_company_ids
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
