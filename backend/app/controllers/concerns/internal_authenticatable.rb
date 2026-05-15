# frozen_string_literal: true

module InternalAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_internal!
  end

  private

  def authenticate_internal!
    token = request.headers["X-Internal-Token"].to_s
    expected = ENV.fetch("INTERNAL_API_TOKEN", "dev-internal-token")
    return if ActiveSupport::SecurityUtils.secure_compare(token, expected)

    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
