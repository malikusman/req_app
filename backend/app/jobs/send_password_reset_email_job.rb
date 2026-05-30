# frozen_string_literal: true

class SendPasswordResetEmailJob < ApplicationJob
  queue_as :default

  def perform(user_type, user_id, reset_url)
    case user_type
    when "company"
      user = CompanyUser.find_by(id: user_id)
      AuthMailer.company_password_reset(user, reset_url).deliver_now if user
    when "reviewer"
      user = ReviewerUser.find_by(id: user_id)
      AuthMailer.reviewer_password_reset(user, reset_url).deliver_now if user
    end
  end
end
