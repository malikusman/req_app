# frozen_string_literal: true

module InternalAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_internal!
  end

  private

  def authenticate_internal!
    expected = ENV["INTERNAL_API_TOKEN"].to_s
    if expected.blank?
      raise "INTERNAL_API_TOKEN is not configured" if Rails.env.production?

      return render json: { error: "unauthorized" }, status: :unauthorized
    end

    token = request.headers["X-Internal-Token"].to_s
    return if token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)

    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
