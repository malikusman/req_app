# frozen_string_literal: true

class AuthMailer < ApplicationMailer
  default from: ENV.fetch("FROM_EMAIL", "notifications@reqapp.local")

  def company_password_reset(user, reset_url)
    @user = user
    @reset_url = reset_url
    mail(to: user.email, subject: "Reset your company portal password")
  end

  def reviewer_password_reset(user, reset_url)
    @user = user
    @reset_url = reset_url
    mail(to: user.email, subject: "Reset your reviewer portal password")
  end
end
