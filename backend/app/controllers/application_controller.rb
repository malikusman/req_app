# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include ActionController::DataStreaming

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  private

  def not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def unprocessable(exception)
    render json: { errors: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def render_errors(messages, status: :unprocessable_entity)
    render json: { errors: Array(messages) }, status: status
  end

  def forbidden
    render json: { error: "Forbidden" }, status: :forbidden
  end
end
